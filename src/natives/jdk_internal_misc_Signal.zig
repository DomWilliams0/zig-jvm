const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_misc_Signal_findSignal0", .desc = "(Ljava/lang/String;)I" },
    .{ .method = "Java_jdk_internal_misc_Signal_handle0", .desc = "(IJ)J" },
    .{ .method = "Java_jdk_internal_misc_Signal_raise0", .desc = "(I)V" },
};
