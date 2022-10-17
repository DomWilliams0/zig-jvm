const std = @import("std");
const object = @import("object.zig");
const cafebabe = @import("cafebabe.zig");

/// Owns handles to loaded native libraries, each classloader owns one
pub const NativeLibraries = struct {
    /// Key is owned, duped by handles.alloc
    handles: std.StringHashMap(NativeLibrary),

    pub fn new(alloc: std.mem.Allocator) @This() {
        return .{
            .handles = std.StringHashMap(NativeLibrary).init(alloc),
        };
    }

    /// Name is borrowed and possibly duped
    pub fn lookupOrLoad(self: *@This(), name: []const u8) !NativeLibrary {
        if (self.handles.get(name)) |lib| return lib;

        // load now
        const lib = try NativeLibrary.load(self.handles.allocator, name);
        try self.handles.put(try self.handles.allocator.dupe(u8, name), lib);

        return lib;
    }

    pub fn deinit(self: *@This()) void {
        var it = self.handles.iterator();
        while (it.next()) |e| {
            self.handles.allocator.free(e.key_ptr.*);
            e.value_ptr.deinit();
        }

        self.handles.deinit();
    }
};

extern "c" fn dlerror() ?[*:0]const u8;
extern "c" fn dlopen(path: [*c]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: *anyopaque, symbol: [*c]const u8) ?*anyopaque;
pub const NativeLibrary = struct {
    lib: *anyopaque,

    pub fn openSelf() !@This() {
        const handle = dlopen(null, std.os.system.RTLD.LAZY) orelse {
            const err = dlerror() orelse "unknown";

            std.log.warn("failed to dlopen self: {s}", .{err});
            return error.Dlopen;
        };

        return .{ .lib = handle };
    }

    /// Alloc is used for temporary lib name expansion to e.g. libXYZ.so
    pub fn load(alloc: std.mem.Allocator, name: []const u8) !@This() {
        const path = switch (@import("builtin").os.tag) {
            .linux, .freebsd, .openbsd => try std.fmt.allocPrint(alloc, "lib{s}.so\x00", .{name}),
            else => @compileError("unsupported platform"),
        };
        defer alloc.free(path);

        std.log.debug("loading native lib '{s}'", .{path});
        // TODO look in java.library.path or sun.boot.library.path
        const lib = dlopen(path, std.os.system.RTLD.LAZY) orelse {
            const err = dlerror() orelse "unknown";

            std.log.warn("failed to open native library '{s}': {s}", .{ path, err });
            return error.Dlopen;
        };
        // TODO call jni constructor

        return .{ .lib = lib };
    }

    pub fn deinit(self: *@This()) void {
        // TODO call jni destructor

        _ = std.os.system.dlclose(self.lib);
        self.* = undefined;
    }

    pub fn resolve(self: *const @This(), symbol: [*:0]const u8) ?*anyopaque {
        std.log.debug("looking for '{s}'", .{symbol});

        // dlsym (and other dl-functions) secretly take shadow parameter - return address on stack
        // https://gcc.gnu.org/bugzilla/show_bug.cgi?id=66826
        return if (@call(.{ .modifier = .never_tail }, dlsym, .{ self.lib, symbol })) |sym|
            @ptrCast(*anyopaque, sym)
        else blk: {
            if (dlerror()) |err|
                std.log.warn("nah {s}", .{err});
            break :blk null;
        };
    }
};

pub const NativeCode = struct {
    lock: std.Thread.RwLock,
    /// Protected by lock
    inner: NativeCodeInner,

    pub fn new() @This() {
        return .{ .lock = .{}, .inner = .unbound };
    }

    pub fn ensure_bound(self: *@This(), class: object.VmClassRef, method: *const cafebabe.Method) !void {
        {
            self.lock.lockShared();
            defer self.lock.unlockShared();

            switch (self.inner) {
                .unbound => {}, // bind now
                .failed_to_bind => return error.FailedToBind,
                .bound => return, // already done
            }
        }

        // bind now
        self.lock.lock();
        defer self.lock.unlock();
        // https://docs.oracle.com/en/java/javase/18/docs/specs/jni/design.html#resolving-native-method-names

        std.log.debug("binding native method", .{});

        var classloader = @import("jvm.zig").thread_state().global.classloader;
        _ = classloader.findNativeMethod(class.get().loader, method);

        @panic("TODO bind");
    }
};

const NativeCodeInner = union(enum) {
    unbound,
    bound: BoundNativeCode,
    failed_to_bind, // TODO store exception
};

const BoundNativeCode = union(enum) {
    jni: @import("jni.zig").NativeMethodCode,
};
