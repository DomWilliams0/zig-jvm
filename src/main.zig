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

    const jvm_args = try arg.JvmArgs.parse(alloc, raw_args);
    if (jvm_args) |args| {
        // TODO put this into JvmArgs
        std.log.debug("args:", .{});
        std.log.debug(" main_class: {s}", .{args.main_class});
        std.log.debug(" classpath: {?s}", .{args.classpath.slice});
        std.log.debug(" bootclasspath: {?s}", .{args.boot_classpath.slice});
    } else {
        std.log.info("TODO show usage", .{});
        return;
    }

    var jvm_handle = try jvm.ThreadEnv.initMainThread(alloc);
    defer jvm_handle.deinit();

    bootstrap.initBootstrapClasses(&jvm_handle.global.classloader);

    // var arena_alloc = std.heap.ArenaAllocator.init(alloc);
    // defer arena_alloc.deinit();
    // const arena = arena_alloc.allocator();
    // _ = try cafebabe.ClassFile.load(arena, alloc, path);

    std.log.info("done", .{});
}
