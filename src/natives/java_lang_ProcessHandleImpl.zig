const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_ProcessHandleImpl_initNative", .desc = "()V" },
    .{ .method = "Java_java_lang_ProcessHandleImpl_waitForProcessExit0", .desc = "(JZ)I" },
    .{ .method = "Java_java_lang_ProcessHandleImpl_getCurrentPid0", .desc = "()J" },
    .{ .method = "Java_java_lang_ProcessHandleImpl_parent0", .desc = "(JJ)J" },
    .{ .method = "Java_java_lang_ProcessHandleImpl_getProcessPids0", .desc = "(J[J[J[J)I" },
    .{ .method = "Java_java_lang_ProcessHandleImpl_destroy0", .desc = "(JJZ)Z" },
    .{ .method = "Java_java_lang_ProcessHandleImpl_isAlive0", .desc = "(J)J" },
};
