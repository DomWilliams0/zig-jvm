const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const arg = @import("arg.zig");
const jvm = @import("jvm.zig");
const bootstrap = @import("bootstrap.zig");

pub const JvmError = error{
    BadArgs,
};

pub const log_level: std.log.Level = .debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const raw_args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, raw_args);

    const jvm_args = try arg.JvmArgs.parse(alloc, raw_args) orelse {
        std.log.info("TODO show usage", .{});
        return;
    };

    // TODO put this into JvmArgs
    std.log.debug("args:", .{});
    std.log.debug(" main_class: {s}", .{jvm_args.main_class});
    std.log.debug(" classpath: {?s}", .{jvm_args.classpath.slice});
    std.log.debug(" bootclasspath: {?s}", .{jvm_args.boot_classpath.slice});

    var jvm_handle = try jvm.ThreadEnv.initMainThread(alloc, &jvm_args);
    defer jvm_handle.deinit();

    // TODO exception
    try bootstrap.initBootstrapClasses(
        &jvm_handle.global.classloader,
    );

    std.log.info("done", .{});
}
