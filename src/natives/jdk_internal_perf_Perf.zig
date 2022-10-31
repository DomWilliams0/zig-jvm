const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_perf_Perf_attach", .desc = "(Ljava/lang/String;II)Ljava/nio/ByteBuffer;" },
    .{ .method = "Java_jdk_internal_perf_Perf_detach", .desc = "(Ljava/nio/ByteBuffer;)V" },
    .{ .method = "Java_jdk_internal_perf_Perf_createLong", .desc = "(Ljava/lang/String;IIJ)Ljava/nio/ByteBuffer;" },
    .{ .method = "Java_jdk_internal_perf_Perf_createByteArray", .desc = "(Ljava/lang/String;II[BI)Ljava/nio/ByteBuffer;" },
    .{ .method = "Java_jdk_internal_perf_Perf_highResCounter", .desc = "()J" },
    .{ .method = "Java_jdk_internal_perf_Perf_highResFrequency", .desc = "()J" },
    .{ .method = "Java_jdk_internal_perf_Perf_registerNatives", .desc = "()V" },
};
