const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_eventSize", .desc = "()I" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_eventOffsets", .desc = "()[I" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_inotifyInit", .desc = "()I" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_inotifyAddWatch", .desc = "(IJI)I" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_inotifyRmWatch", .desc = "(II)V" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_configureBlocking", .desc = "(IZ)V" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_socketpair", .desc = "([I)V" },
    .{ .method = "Java_sun_nio_fs_LinuxWatchService_poll", .desc = "(II)I" },
};
