const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const arg = @import("arg.zig");
const jvm = @import("jvm.zig");
const bootstrap = @import("bootstrap.zig");
const Allocator = std.mem.Allocator;

pub const log_level: std.log.Level = .debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const raw_args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, raw_args);

    var jvm_args = try arg.JvmArgs.parse(alloc, raw_args, .{ .require_main_class = false }) orelse {
        std.log.info("TODO show test usage", .{});
        return;
    };

    try jvm_args.boot_classpath.addExtra(Test.class_dir);

    std.log.debug("args:", .{});
    std.log.debug(" classpath: {?s}", .{jvm_args.classpath.slice});
    std.log.debug(" bootclasspath: {?s}", .{jvm_args.boot_classpath.slice});

    var jvm_handle = try jvm.ThreadEnv.initMainThread(alloc, &jvm_args);
    defer jvm_handle.deinit();

    try bootstrap.initBootstrapClasses(
        &jvm_handle.global.classloader,
        .{ .no_initialise = true },
    );

    var test_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const test_alloc = test_gpa.allocator();
    const test_filter = std.os.getenv("ZIG_JVM_TEST_FILTER");
    const tests = try Test.discover(test_alloc, test_filter);
    defer tests.deinit();

    try Test.prepareForAll();
    for (tests.items) |t, i| {
        t.run(test_alloc) catch std.debug.panic("TEST {s} FAILED", .{t.testName()});
        std.log.info("test {d}/{d} {s} passed", .{ i + 1, tests.items.len, t.testName() });
    }

    std.log.info("all {d} tests passed", .{tests.items.len});
}

const Test = struct {
    src_path: []const u8,

    fn discover(alloc: Allocator, filter: ?[]const u8) !std.ArrayList(Test) {
        const path = try std.fs.realpathAlloc(alloc, "./src/test");
        std.log.debug("looking for tests in {s}", .{path});
        defer alloc.free(path);

        var dir = try std.fs.openIterableDirAbsolute(path, .{});
        defer dir.close();

        var iter = dir.iterate();
        var tests = std.ArrayList(Test).init(alloc);
        errdefer tests.deinit();
        while (try iter.next()) |it| {
            if (it.kind == .File and std.mem.endsWith(u8, it.name, ".java")) {
                if (filter) |f| {
                    if (std.mem.indexOf(u8, it.name, f) == null) continue;
                }
                const src_path = try std.mem.concat(alloc, u8, &.{ path, "/", it.name });
                std.log.debug("found test {s}", .{it.name});
                try tests.append(Test{ .src_path = src_path });
            }
        }

        return tests;
    }

    const E = error{
        Compile,
        MissingEntrypoint,
        Failed,
    };

    // TODO configure at runtime
    const class_dir: []const u8 = "/tmp/zig-jvm-classes";

    fn prepareForAll() !void {
        std.fs.deleteTreeAbsolute(class_dir) catch {};
    }

    fn testName(self: @This()) []const u8 {
        const fileName = std.fs.path.basenamePosix(self.src_path);
        const suffix = ".java";
        _ = suffix;
        return fileName[0 .. fileName.len - ".java".len];
    }

    fn run(self: Test, alloc: Allocator) !void {

        // compile
        std.log.debug("compiling {s}", .{std.fs.path.basename(self.src_path)});
        var javac = std.ChildProcess.init(&.{ "javac", "-d", class_dir, self.src_path }, alloc);
        const res = try javac.spawnAndWait();
        if (res != .Exited or res.Exited != 0) {
            std.log.err("test failed to compile: {any}", .{res});
            return E.Compile;
        }

        // load test class
        const cls = try jvm.thread_state().global.classloader.loadClass(self.testName(), .bootstrap);

        // find test method
        const entrypoint = cls.get().findMethodInThisOnly("vmTest", "()I", .{ .public = true, .static = true }) orelse return E.MissingEntrypoint;

        // run the test
        const ret_value = try jvm.thread_state().interpreter.executeUntilReturn(cls, entrypoint);
        const ret_code = ret_value.convertTo(i32);

        // ensure success
        if (ret_code != 0) {
            std.log.err("test {s} returned {d}", .{ self.testName(), ret_code });
            return E.Failed;
        }
    }
};