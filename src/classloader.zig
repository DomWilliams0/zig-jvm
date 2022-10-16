const std = @import("std");
const jvm = @import("jvm.zig");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

const VmClassRef = object.VmClassRef;
const VmObjectRef = object.VmObjectRef;

pub const WhichLoader = union(enum) {
    bootstrap,
    user: VmObjectRef,

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

    fn deinit(self: @This()) void {
        switch (self) {
            .user => |obj| obj.drop(),
            .bootstrap => {},
        }
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
    primitives: [vm_type.primitives.len]VmClassRef.Nullable = [_]VmClassRef.Nullable{VmClassRef.Nullable.nullRef()} ** vm_type.primitives.len,

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
        loaded: VmClassRef,
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

        // drop all class references
        var it = self.classes.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            self.alloc.free(key.name);
            key.loader.deinit();
            switch (entry.value_ptr.*) {
                .loaded => |cls| cls.drop(),
                .failed => {}, // TODO drop exception
                else => {},
            }
        }

        self.classes.deinit(self.alloc);
        self.classes = .{};

        for (self.primitives) |prim| {
            if (prim.toStrong()) |p| p.drop();
        }
    }

    /// Same as loadClass("[" ++ name, ...). Must not be a primitive
    pub fn loadClassAsArrayElement(self: *Self, elem_name: []const u8, requested_loader: WhichLoader) anyerror!VmClassRef {
        // prepend [
        var array_cls_name: []u8 = try self.alloc.alloc(u8, elem_name.len + 1);
        array_cls_name[0] = '[';
        std.mem.copy(u8, array_cls_name[1..], elem_name);

        return self.loadClassInternal(array_cls_name, requested_loader, .reference);
    }

    const ArrayType = enum {
        not,
        primitive,
        reference,
    };

    /// Main entrypoint - name can be array or class name. Loads now if not already.
    /// Loader is cloned if needed for loading.
    /// Returns BORROWED reference
    // TODO return exception or error type
    pub fn loadClass(self: *Self, name: []const u8, requested_loader: WhichLoader) anyerror!VmClassRef {
        // TODO exception
        if (name.len < 2) std.debug.panic("class name too short {s}", .{name});

        // TODO helper wrapper type around type names like java/lang/String and [[C ?
        const array_type: ArrayType = if (name[0] == '[')
            if (name[1] == 'L' or name[1] == '[')
                .reference
            else
                .primitive
        else
            .not;

        // use bootstrap loader for primitive arrays
        var loader = if (array_type == .primitive) .bootstrap else requested_loader;

        if (array_type == .reference) {
            unreachable; // TODO load element class first
        }

        return self.loadClassInternal(name, loader, array_type);
    }

    fn loadClassInternal(self: *Self, name: []const u8, loader: WhichLoader, array_type: ArrayType) anyerror!VmClassRef {
        switch (self.getLoadState(name, loader)) {
            .loading => unreachable, // TODO other threads
            .loaded => |cls| return cls,
            else => {},
        }

        // loading time
        // TODO native error to exception?
        try self.setLoadState(name, loader, .{ .loading = Thread.getCurrentId() });

        const loaded_res = switch (loader) {
            .bootstrap => if (array_type == .not) self.loadBootstrapClass(name) else self.loadArrayClass(name, array_type == .primitive, loader),
            .user => |_| {
                std.debug.assert(array_type != .primitive); // already filtered out
                unreachable; // TODO user loader
            },
        };

        if (loaded_res) |cls| {
            self.setLoadState(name, loader, .{ .loaded = cls }) catch unreachable; // already in there
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
    fn loadBootstrapClass(self: *Self, name: []const u8) !VmClassRef {
        // TODO should allocate in big blocks rather than using gpa for all tiny allocs
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();

        const file_bytes = try findBootstrapClassFile(arena.allocator(), self.alloc, name) orelse return E.ClassNotFound;
        return self.defineClass(arena.allocator(), name, file_bytes, .bootstrap);
    }

    // TODO set exception
    fn loadArrayClass(self: *Self, name: []const u8, is_primitive: bool, loader: WhichLoader) !VmClassRef {
        std.debug.assert(name[0] == '[');
        const elem_name = name[1..];

        const elem_class_ref = try if (is_primitive) self.loadPrimitive(elem_name) else self.loadClass(elem_name, loader);
        const elem_class = elem_class_ref.get();

        var flags = elem_class.flags;
        if (!is_primitive) flags.remove(.interface) else flags.insert(.public);
        flags.insert(.abstract);
        flags.insert(.final);

        // TODO faster lookup
        const java_lang_Object = self.getLoadedBootstrapClass("java/lang/Object") orelse unreachable;

        // TODO interfaces cloneable and serializable
        const elem_dims = if (elem_class.name[0] == '[') elem_class.u.array.dims else 0;

        var class = try vm_alloc.allocClass();
        const padding = elem_class.calculateArrayPreElementPadding();
        class.get().* = .{
            .flags = flags,
            .name = try self.alloc.dupe(u8, name),
            .u = .{ .array = .{ .elem_cls = elem_class_ref.clone(), .dims = elem_dims + 1, .padding = padding } },
            .status = .{ .ty = .array },
            .super_cls = java_lang_Object.clone(),
            .interfaces = &.{}, // TODO
            .loader = loader.clone(),
            .class_instance = try self.allocJavaLangClassInstance(),
        };

        return class;
    }

    // TODO cached/better lookup for known bootstrap classes
    /// Returns BORROWED reference
    pub fn getLoadedBootstrapClass(self: *Self, name: []const u8) ?VmClassRef {
        return switch (self.getLoadState(name, .bootstrap)) {
            .loaded => |cls| cls,
            else => null,
        };
    }

    /// Name should be static if loading for the first time (during startup).
    /// Returns BORROWED class reference
    pub fn loadPrimitive(self: *Self, name: []const u8) anyerror!VmClassRef {
        const ty = vm_type.PrimitiveDataType.fromTypeString(name) orelse std.debug.panic("invalid primitive {s}", .{name});
        return self.loadPrimitiveWithType(name, ty);
    }

    /// Name should be static if loading for the first time (during startup).
    /// Returns BORROWED class reference
    pub fn loadPrimitiveWithType(self: *Self, name: []const u8, ty: vm_type.PrimitiveDataType) anyerror!VmClassRef {
        var entry = &self.primitives[@enumToInt(ty)];
        if (entry.toStrong()) |cls| return cls;

        std.log.debug("loading primitive {s}", .{name});

        var class = try vm_alloc.allocClass();
        class.get().* = .{
            .flags = std.EnumSet(cafebabe.ClassFile.Flags).init(.{ .public = true, .final = true, .abstract = true }),
            .name = name, // static
            .u = .{ .primitive = ty },
            .super_cls = null,
            .status = .{ .ty = .primitive },
            .interfaces = &.{},
            .loader = .bootstrap,
            .class_instance = try self.allocJavaLangClassInstance(),
        };

        entry.* = class.intoNullable();
        return class; // borrowed
    }

    pub fn allocJavaLangClassInstance(self: *Self) !VmObjectRef.Nullable {
        const java_lang_Class = self.getLoadedBootstrapClass("java/lang/Class") orelse return VmObjectRef.Nullable.nullRef();

        const obj = object.VmClass.instantiateObject(java_lang_Class);

        // TODO set fields

        return obj.intoNullable();
    }

    /// Class bytes are the callers responsiblity to clean up.
    /// Not an array or primitive.
    fn defineClass(self: *Self, arena: Allocator, name: []const u8, class_bytes: []const u8, loader: WhichLoader) !VmClassRef {
        var stream = std.io.fixedBufferStream(class_bytes);
        var classfile = try cafebabe.ClassFile.parse(arena, self.alloc, &stream);
        errdefer classfile.deinit(self.alloc);

        if (!std.mem.eql(u8, name, classfile.this_cls)) return E.NameMismatch;

        // linking

        // resolve super
        var super_class = if (classfile.super_cls) |super| (try self.loadClass(super, loader)).clone() else null;

        var class = try vm_alloc.allocClass();
        class.get().* = .{
            .flags = classfile.flags,
            .name = classfile.this_cls,
            .super_cls = super_class,
            .interfaces = &.{}, // TODO
            .status = .{ .ty = .object },
            .u = .{
                .obj = .{
                    .fields = classfile.fields,
                    .methods = classfile.methods,
                    .constant_pool = classfile.constant_pool,
                    .layout = undefined, // set next in preparation stage
                },
            },
            .loader = loader.clone(),
            .class_instance = try self.allocJavaLangClassInstance(),
        };

        // preparation
        var layout: object.ObjectLayout = if (!classfile.flags.contains(cafebabe.ClassFile.Flags.interface)) .{} else if (super_class) |super| super.get().u.obj.layout else .{};
        try object.defineObjectLayout(arena, class.get().u.obj.fields, &layout);
        class.get().u.obj.layout = layout;
        std.log.debug("{s} has layout {any}", .{ name, layout });

        // TODO interfaces are not yet implemented
        classfile.interfaces.deinit(self.alloc);
        return class;
    }

    /// Arena is only used for the successfully read class file bytes
    // TODO error set and proper exception returning
    // TODO class name to path encoding
    fn findBootstrapClassFile(arena: Allocator, alloc: Allocator, name: []const u8) std.mem.Allocator.Error!?[]const u8 {
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

            break io.readFile(arena, path, candidate_abs) catch continue;
        } else return null;
    }
};
