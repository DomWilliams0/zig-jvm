const std = @import("std");
const classloader = @import("classloader.zig");
const vm_alloc = @import("alloc.zig");
const JvmArgs = @import("arg.zig").JvmArgs;
const Allocator = std.mem.Allocator;

threadlocal var thread_env: ThreadEnv = undefined;
threadlocal var inited = false;

/// All threads have a reference. Owned by main thread
pub const GlobalState = struct {
    non_daemon_threads: u32,
    daemon_threads: u32,

    classloader: classloader.ClassLoader,
    allocator: vm_alloc.VmAllocator,
    args: *const JvmArgs,
};

/// Each thread owns one
pub const ThreadEnv = struct {
    global: *GlobalState,

    fn init(global: *GlobalState) ThreadEnv {
        return ThreadEnv{ .global = global };
    }

    pub fn initMainThread(alloc: Allocator, args: *const JvmArgs) !JvmHandle {
        var global = try alloc.create(GlobalState);
        // TODO errdefer global.deinit();
        errdefer alloc.destroy(global);
        global.* = .{
            .non_daemon_threads = 1, // main thread
            .daemon_threads = 0,
            .classloader = try classloader.ClassLoader.new(alloc),
            .allocator = vm_alloc.VmAllocator{ .inner = alloc },
            .args = args,
        };

        _ = initThread(global);
        return .{
            .global = global,
            .main_thread = std.Thread.getCurrentId(),
        };
    }

    /// Inits threadlocal
    pub fn initThread(global: *GlobalState) *ThreadEnv {
        if (inited) @panic("init once only");
        thread_env = .{
            .global = global,
        };
        inited = true;

        return &thread_env;
    }
};

/// "Owns" the JVM main thread, created by user code
pub const JvmHandle = struct {
    global: *GlobalState,
    main_thread: std.Thread.Id,

    /// TODO optionally detach and leave daemons running, or kill everything and release all desources
    pub fn deinit(self: JvmHandle) void {
        if (self.main_thread != std.Thread.getCurrentId())
            std.debug.panic("jvm handle must be deinit'd on the main thread", .{});

        if (self.global.daemon_threads != 0 or self.global.non_daemon_threads != 1)
            std.debug.panic("TODO join threads", .{});

        // all other threads should be dead now, clear threadlocals
        std.log.info("destroying main thread", .{});
        thread_env = undefined;
        inited = false;

        // just free memory now
        const alloc = self.global.allocator.inner;
        alloc.destroy(self.global);
        var self_mut = self;
        self_mut.global = undefined;
    }
};

pub fn thread_state() *ThreadEnv {
    std.debug.assert(inited);
    return &thread_env;
}
