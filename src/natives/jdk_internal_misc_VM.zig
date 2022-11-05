const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_jdk_internal_misc_VM_initialize() void {}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_misc_VM_latestUserDefinedLoader0", .desc = "()Ljava/lang/ClassLoader;" },
    .{ .method = "Java_jdk_internal_misc_VM_getuid", .desc = "()J" },
    .{ .method = "Java_jdk_internal_misc_VM_geteuid", .desc = "()J" },
    .{ .method = "Java_jdk_internal_misc_VM_getgid", .desc = "()J" },
    .{ .method = "Java_jdk_internal_misc_VM_getegid", .desc = "()J" },
    .{ .method = "Java_jdk_internal_misc_VM_getNanoTimeAdjustment", .desc = "(J)J" },
    .{ .method = "Java_jdk_internal_misc_VM_getRuntimeArguments", .desc = "()[Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_misc_VM_initialize", .desc = "()V" },
};
