const std = @import("std");
const jvm = @import("jvm.zig");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const object = @import("object.zig");
const Allocator = std.mem.Allocator;

pub const WhichLoader = union(enum) {
    bootstrap,
    user: object.VmObjectRef,
};
pub const E = error{
    ClassNotFound, // TODO exception instead
    NameMismatch,
};

pub const ClassLoader = struct {
    const Self = @This();

    alloc: Allocator,

    pub fn new(alloc: Allocator) !ClassLoader {
        return ClassLoader{ .alloc = alloc };
    }

    // TODO return exception
    pub fn loadClass(self: *Self, name: []const u8, loader: WhichLoader) anyerror!object.VmClassRef {

        // TODO check for array
        // TODO helper wrapper type around type names like java/lang/String and [[C ?
        std.debug.assert(name.len > 0 and name[0] != '['); // TODO array classes

        // TODO return already loaded instance

        return switch (loader) {
            .bootstrap => self.loadBootstrapClass(name),
            .user => |_| unreachable, // TODO
        };
    }

    /// Name is the file name of the class
    // TODO set exception
    pub fn loadBootstrapClass(self: *Self, name: []const u8) !object.VmClassRef {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        errdefer arena.deinit();

        const file_bytes = try findBootstrapClassFile(&arena, self.alloc, name) orelse return E.ClassNotFound;
        return try self.defineClass(&arena, name, file_bytes, .bootstrap);
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

        return class;

        // TODO class does not need static storage, just put value in the Field in the class instance
        // calculate class and object layouts
        // var base = if (classfile.flags.contains(cafebabe.ClassFile.Flags.interface)) null else {

        // };
        // const layout = object.defineObjectLayout(arena, &classfile.fields.items)
        // var class = vm_alloc.allocClass()
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
