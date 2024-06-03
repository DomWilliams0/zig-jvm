const std = @import("std");
const jvm = @import("jvm");

usingnamespace @import("natives");

pub const JvmError = error{
    BadArgs,
};

pub const log_level: std.log.Level = .debug;

pub fn main() !void {
    // TODO add limit to test oom
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    defer if (jvm.alloc.logging) {
        _ = gpa.detectLeaks();
    };

    const raw_args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, raw_args);

    var jvm_args = try jvm.arg.JvmArgs.parse(alloc, raw_args, .{}) orelse {
        std.log.info("TODO show usage", .{});
        return;
    };
    defer jvm_args.deinit();

    // TODO put this into JvmArgs
    std.log.debug("args:", .{});
    std.log.debug(" main_class: {s}", .{jvm_args.main_class});
    std.log.debug(" classpath: {?s}", .{jvm_args.classpath.slice});
    std.log.debug(" bootclasspath: {?s}", .{jvm_args.boot_classpath.slice});

    var jvm_handle = try jvm.state.ThreadEnv.initMainThread(alloc, &jvm_args);
    defer jvm_handle.deinit();

    try jvm.bootstrap.initBootstrapClasses(
        &jvm_handle.global.classloader,
        .{},
    );

    //  TODO get system classloader

    // find main class
    const main_cls = try jvm_handle.global.classloader.loadClass(jvm_args.main_class, .bootstrap);
    // TODO init it (run static constructor)

    // find main method
    const main_method = main_cls.get().findMethodInThisOnly("main", "([Ljava/lang/String;)V", .{ .public = true, .static = true }) orelse unreachable;

    // invoke main
    _ = try jvm.state.thread_state().interpreter.executeUntilReturn(main_method);
    // TODO handle exception like test runner

    std.log.info("done", .{});
}
