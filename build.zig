const std = @import("std");
const Pkg = std.build.Pkg;

const pkg_jvm = Pkg{
    .name = "jvm",
    .source = .{ .path = "src/root.zig" },
};
const pkg_natives = Pkg{ .name = "natives", .source = .{ .path = "src/natives/root.zig" }, .dependencies = &[_]Pkg{
    pkg_jvm,
} };

const pkgs = [2]Pkg{ pkg_jvm, pkg_natives };
var build_helpers = false;

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    var test_runner = false;
    var args = if (b.args) |args|
        for (args) |a, i| {
            if (std.mem.eql(u8, a, "-testrunner")) {
                test_runner = true;

                // remove this arg
                var args_mut = args;
                var j = i + 1;
                while (j < args_mut.len) : (j += 1)
                    args_mut[j - 1] = args_mut[j];
                args_mut.len -= 1;
                break args_mut;
            }
        } else args
    else
        null;

    const exe = if (test_runner)
        b.addExecutable("jvm-test-runner", "src/test-runner.zig")
    else
        b.addExecutable("java", "src/main.zig");

    inline for (pkgs) |pkg| exe.addPackage(pkg);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.rdynamic = true;
    exe.linkSystemLibrary("ffi");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (args) |a| {
        run_cmd.addArgs(a);
    }

    const run_step = b.step("run", "Run JVM (or test runner with -testrunner)");
    run_step.dependOn(&run_cmd.step);

    if (build_helpers) {
        const native_finder = b.addExecutable("native-finder", "src/scripts/native-finder.zig");
        inline for (pkgs) |pkg| native_finder.addPackage(pkg);
        native_finder.setTarget(target);
        native_finder.setBuildMode(mode);
        native_finder.linkLibC();
        native_finder.install();
        const native_finder_cmd = native_finder.run();
        native_finder_cmd.step.dependOn(b.getInstallStep());
        if (args) |a| {
            native_finder_cmd.addArgs(a);
        }

        const native_finder_step = b.step("find-natives", "Discover native methods");
        native_finder_step.dependOn(&native_finder_cmd.step);
    }

    const exe_tests = b.addTest("src/object.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    exe_tests.linkLibC();

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
