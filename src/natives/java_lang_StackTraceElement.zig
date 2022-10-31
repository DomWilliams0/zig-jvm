const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_StackTraceElement_initStackTraceElements", .desc = "([Ljava/lang/StackTraceElement;Ljava/lang/Throwable;)V" },
    .{ .method = "Java_java_lang_StackTraceElement_initStackTraceElement", .desc = "(Ljava/lang/StackTraceElement;Ljava/lang/StackFrameInfo;)V" },
};
