const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_fs_LinuxNativeDispatcher_setmntent0", .desc = "(JJ)J" },
    .{ .method = "Java_sun_nio_fs_LinuxNativeDispatcher_getmntent0", .desc = "(JLsun/nio/fs/UnixMountEntry;JI)I" },
    .{ .method = "Java_sun_nio_fs_LinuxNativeDispatcher_endmntent", .desc = "(J)V" },
    .{ .method = "Java_sun_nio_fs_LinuxNativeDispatcher_init", .desc = "()V" },
};
