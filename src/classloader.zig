const std = @import("std");
const jvm = @import("jvm.zig");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

pub const WhichLoader = union(enum) {
    bootstrap,
    user: object.VmObjectRef,

    fn eq(a: @This(), b: @This()) bool {
        return switch (a) {
            .bootstrap => switch (b) {
                .bootstrap => true,
                else => false,
            },
            .user => |obj_a| switch (b) {
                .user => |obj_b| obj_a.cmpPtr(obj_b),
                else => false,
            },
        };
    }

    fn clone(self: @This()) @This() {
        return switch (self) {
            .bootstrap => .bootstrap,
            .user => |obj| .{ .user = obj.clone() },
        };
    }
};
pub const E = error{
    ClassNotFound, // TODO exception instead
    NameMismatch,
};

pub const ClassLoader = struct {
    const Self = @This();

    alloc: Allocator,

    /// Protects classes map
    lock: Thread.RwLock,
    classes: std.ArrayHashMapUnmanaged(Key, LoadState, ClassesContext, true),

    /// Initialised during startup so not mutex protected
    primitives: [vm_type.primitives.len]?object.VmClassRef = [_]?object.VmClassRef{null} ** vm_type.primitives.len,

    const ClassesContext = struct {
        pub fn hash(_: @This(), key: Key) u32 {
            var hasher = std.hash.Wyhash.init(4);
            hasher.update(key.name);
            std.hash.autoHash(&hasher, key.loader);
            return @truncate(u32, hasher.final());
        }

        pub fn eql(_: @This(), a: Key, b: Key, _: usize) bool {
            return a.loader.eq(b.loader) and std.mem.eql(u8, a.name, b.name);
        }
    };

    const LoadState = union(enum) {
        unloaded,
        loading: Thread.Id,
        loaded: object.VmClassRef,
        failed,
    };

    const Key = struct { name: []const u8, loader: WhichLoader };

    pub fn new(alloc: Allocator) !ClassLoader {
        var cl = ClassLoader{ .alloc = alloc, .lock = .{}, .classes = .{} };
        try cl.classes.ensureTotalCapacity(alloc, 1024);
        return cl;
    }

    pub fn deinit(self: *@This()) void {
        self.lock.lock();
        defer self.lock.unlock();

        self.classes.deinit(self.alloc);
        self.classes = .{};
    }

    // TODO return exception
    pub fn loadClass(self: *Self, name: []const u8, loader: WhichLoader) anyerror!object.VmClassRef {

        // TODO check for array
        // TODO helper wrapper type around type names like java/lang/String and [[C ?
        std.debug.assert(name.len > 0 and name[0] != '['); // TODO array classes

        switch (self.getLoadState(name, loader)) {
            .loading => unreachable, // TODO other threads
            .loaded => |cls| return cls,
            else => {},
        }

        // loading time
        // TODO native error to exception?
        try self.setLoadState(name, loader, .{ .loading = Thread.getCurrentId() });

        const loaded_res = switch (loader) {
            .bootstrap => self.loadBootstrapClass(name),
            .user => |_| unreachable, // TODO user loader
        };

        if (loaded_res) |cls| {
            self.setLoadState(name, loader, .{ .loaded = cls.clone() }) catch unreachable; // already in there
            return cls;
        } else |err| {
            self.setLoadState(name, loader, .failed) catch unreachable; // already in there
            return err;
        }
    }

    fn getLoadState(self: *Self, name: []const u8, loader: WhichLoader) LoadState {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        const key = Key{ .name = name, .loader = loader };
        return self.classes.get(key) orelse .unloaded;
    }

    /// name and loader are owned by the caller, and cloned on first addition (owned by the loader).
    /// Only fails on allocating when adding new entry
    fn setLoadState(self: *Self, name: []const u8, loader: WhichLoader, state: LoadState) !void {
        self.lock.lock();
        defer self.lock.unlock();

        const key = Key{ .name = name, .loader = loader };
        const entry = try self.classes.getOrPut(self.alloc, key);
        if (entry.found_existing)
            entry.value_ptr.* = state
        else {
            entry.key_ptr.name = try self.alloc.dupe(u8, name);
            entry.key_ptr.loader = loader.clone();
        }

        std.log.debug("set {s} state for {s}", .{ @tagName(state), name });
    }

    /// Name is the file name of the class
    // TODO set exception
    fn loadBootstrapClass(self: *Self, name: []const u8) !object.VmClassRef {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        errdefer arena.deinit();

        const file_bytes = try findBootstrapClassFile(&arena, self.alloc, name) orelse return E.ClassNotFound;
        return try self.defineClass(&arena, name, file_bytes, .bootstrap);
    }

    // TODO cached/better lookup for known bootstrap classes
    fn getLoadedBootstrapClass(self: *Self, name: []const u8) ?object.VmClassRef {
        return switch (self.getLoadState(name, .bootstrap)) {
            .loaded => |cls| cls,
            else => null,
        };
    }

    pub fn loadPrimitive(self: *Self, name: []const u8) anyerror!object.VmClassRef {
        const ty = vm_type.DataType.fromName(name, true) orelse std.debug.panic("invalid primitive {s}", name);
        return self.loadPrimitiveWithType(name, ty);
    }

    /// Name should be static if lodaing for the first time (during startup)
    pub fn loadPrimitiveWithType(self: *Self, name: []const u8, ty: vm_type.DataType) anyerror!object.VmClassRef {
        var entry = &self.primitives[@enumToInt(ty)];
        if (entry.*) |cls| return cls;

        std.log.debug("loading primitive {s}", .{name});

        var class = try vm_alloc.allocClass();
        class.get().* = .{
            .constant_pool = undefined,
            .flags = std.EnumSet(cafebabe.ClassFile.Flags).init(.{ .public = true, .final = true, .abstract = true }),
            .name = name, // static
            .super_cls = undefined,
            .interfaces = undefined,
            .fields = undefined,
            .attributes = undefined,
            .layout = .{ .primitive = ty },
        };

        entry.* = class.clone();

        return class;
    }

    /// Class bytes are the callers responsiblity to clean up.
    fn defineClass(self: *Self, arena: *std.heap.ArenaAllocator, name: []const u8, class_bytes: []const u8, loader: WhichLoader) !object.VmClassRef {
        var stream = std.io.fixedBufferStream(class_bytes);
        var classfile = try cafebabe.ClassFile.parse(arena, self.alloc, &stream);
        errdefer classfile.deinit(self.alloc);

        if (!std.mem.eql(u8, name, classfile.this_cls)) return E.NameMismatch;

        // linking

        // resolve super
        var super_class = if (classfile.super_cls) |super| try self.loadClass(super, loader) else null;

        var class = try vm_alloc.allocClass();
        class.get().* = .{
            .constant_pool = classfile.constant_pool, // TODO dont put into arena then
            .flags = classfile.flags,
            .name = try self.alloc.dupe(u8, classfile.this_cls),
            .super_cls = super_class,
            .interfaces = undefined, // TODO
            .fields = blk: {
                const slice = classfile.fields.allocatedSlice();
                classfile.fields = .{}; // take ownership
                break :blk slice;
            },
            .attributes = blk: {
                const slice = classfile.attributes.allocatedSlice();
                classfile.attributes = .{}; // take ownership
                break :blk slice;
            },
            .layout = undefined, // set soon in preparation stage
        };

        // preparation
        // not a primitive, could be an array TODO
        const is_array = false;
        if (!is_array) {
            var layout: object.ObjectLayout = if (classfile.flags.contains(cafebabe.ClassFile.Flags.interface)) .{} else if (super_class) |super| super.get().layout.fields else .{};
            try object.defineObjectLayout(arena.allocator(), class.get().fields, &layout);
            class.get().layout = .{ .fields = layout };
        }

        return class;
    }

    /// Arena is only used for the successfully read class file bytes
    // TODO error set and proper exception returning
    // TODO class name to path encoding
    fn findBootstrapClassFile(arena: *std.heap.ArenaAllocator, alloc: Allocator, name: []const u8) std.mem.Allocator.Error!?[]const u8 {
        const thread = jvm.thread_state();

        var buf_backing = try alloc.alloc(u8, std.fs.MAX_PATH_BYTES * 2);
        defer alloc.free(buf_backing);

        var candidate_rel = buf_backing[0..std.fs.MAX_PATH_BYTES];
        var candidate_abs = buf_backing[std.fs.MAX_PATH_BYTES .. std.fs.MAX_PATH_BYTES * 2];

        const io = struct {
            pub fn readFile(io_arena: Allocator, rel_path: []const u8, abs_path_buf: *[std.fs.MAX_PATH_BYTES]u8) ![]const u8 {
                const path_abs = try std.fs.realpath(rel_path, abs_path_buf); // TODO expand path too e.g. ~, env vars

                var file = try std.fs.openFileAbsolute(path_abs, .{});
                const sz = try file.getEndPos();

                std.log.debug("loading class file {s} ({d} bytes)", .{ path_abs, sz });
                const file_bytes = try io_arena.alloc(u8, sz);

                const n = try file.readAll(file_bytes);
                if (n != sz) std.log.warn("only read {d}/{d} bytes", .{ n, sz });
                return file_bytes;
            }
        };

        var it = thread.global.args.boot_classpath.iterator();
        return while (it.next()) |entry| {
            // TODO support zip entries
            // TODO support modules

            const path = std.fmt.bufPrint(candidate_rel, "{s}/{s}.class", .{ entry, name }) catch continue;
            // TODO why cant we open files by relative path?

            break io.readFile(arena.allocator(), path, candidate_abs) catch continue;
        } else return null;
    }
};
