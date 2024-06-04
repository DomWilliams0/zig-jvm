const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const jvm = b.addModule("jvm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const natives = b.createModule(.{
        .root_source_file = b.path("src/natives/root.zig"),
        .imports = &.{
            .{ .name = "jvm", .module = jvm },
        },
        .target = target,
        .optimize = optimize,
    });

    const test_runner_step = b.step("testrunner", "Build integration tests to run against suite of small Java programs");
    const jvm_step = b.step("java", "Build JVM");

    const test_runner_exe = b.addExecutable(.{ .name = "jvm-test-runner", .root_source_file = b.path("src/test-runner.zig"), .target = target, .optimize = optimize });
    const java_exe = b.addExecutable(.{ .name = "java", .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });

    inline for (.{ .{ test_runner_step, test_runner_exe }, .{ jvm_step, java_exe } }) |tup| {
        const step, const exe = tup;

        // exe.use_llvm = false;
        // exe.use_lld = false;

        exe.root_module.addImport("jvm", jvm);
        exe.root_module.addImport("natives", natives);
        exe.linkLibC();
        exe.linkSystemLibrary("ffi");
        exe.rdynamic = true;
        b.installArtifact(exe);
        step.dependOn(&exe.step);

        var buf: [128]u8 = undefined;
        const run_step_name = try std.fmt.bufPrint(&buf, "run-{s}", .{step.name});
        const run_step = b.step(run_step_name, "Run");
        var run_artifact = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_artifact.addArgs(args);
        }
        run_step.dependOn(&run_artifact.step);
    }

    // b.getInstallStep().dependOn(test_runner_step);
    // b.getInstallStep().dependOn(jvm_step);

    const exe_tests = b.addTest(.{ .root_source_file = b.path("src/root.zig"), .target = target });
    exe_tests.linkLibC();
    exe_tests.linkSystemLibrary("ffi");
    const test_step = b.step("test", "Run unit tests");
    const run_unit_tests = b.addRunArtifact(exe_tests);
    test_step.dependOn(&run_unit_tests.step);
}

//     if (build_helpers) {
//         const native_finder = b.addExecutable("native-finder", "src/scripts/native-finder.zig");
//         inline for (pkgs) |pkg| native_finder.addPackage(pkg);
//         native_finder.setTarget(target);
//         native_finder.setBuildMode(mode);
//         native_finder.linkLibC();
//         native_finder.install();
//         const native_finder_cmd = native_finder.run();
//         native_finder_cmd.step.dependOn(b.getInstallStep());
//         if (args) |a| {
//             native_finder_cmd.addArgs(a);
//         }

//         const native_finder_step = b.step("find-natives", "Discover native methods");
//         native_finder_step.dependOn(&native_finder_cmd.step);
//     }
