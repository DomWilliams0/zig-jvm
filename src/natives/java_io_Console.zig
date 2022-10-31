const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_Console_encoding", .desc = "()Ljava/lang/String;" },
    .{ .method = "Java_java_io_Console_echo", .desc = "(Z)Z" },
    .{ .method = "Java_java_io_Console_istty", .desc = "()Z" },
};
