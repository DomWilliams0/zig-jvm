const std = @import("std");
const Pkg = std.build.Pkg;

const pkg_jni = Pkg{
    .name = "sys",
    .source = .{ .path = "src/sys/jni.zig" },
};
const pkg_jvm = Pkg{
    .name = "jvm",
    .source = .{ .path = "src/root.zig" },
};
const pkg_natives = Pkg{ .name = "natives", .source = .{ .path = "src/natives/root.zig" }, .dependencies = &[_]Pkg{pkg_jni} };

const pkgs = [3]Pkg{ pkg_jni, pkg_jvm, pkg_natives };

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-jvm", "src/main.zig");
    inline for (pkgs) |pkg| exe.addPackage(pkg);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.rdynamic = true;
    exe.linkSystemLibrary("ffi");
    exe.install();

    const test_runner = b.addExecutable("jvm-test-runner", "src/test-runner.zig");
    inline for (pkgs) |pkg| test_runner.addPackage(pkg);
    test_runner.setTarget(target);
    test_runner.setBuildMode(mode);
    test_runner.linkLibC();
    test_runner.rdynamic = true;
    test_runner.linkSystemLibrary("ffi");
    test_runner.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const testrunner_cmd = test_runner.run();
    testrunner_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        testrunner_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const testrunner_step = b.step("run-tests", "Runs the test runner");
    testrunner_step.dependOn(&testrunner_cmd.step);

    const exe_tests = b.addTest("src/object.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    exe_tests.linkLibC();

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
