const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_ProcessImpl_forkAndExec", .desc = "(I[B[B[BI[BI[B[IZ)I" },
    .{ .method = "Java_java_lang_ProcessImpl_init", .desc = "()V" },
};
