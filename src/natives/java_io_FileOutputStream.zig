const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_io_FileOutputStream_initIDs() void {}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_FileOutputStream_open0", .desc = "(Ljava/lang/String;Z)V" },
    .{ .method = "Java_java_io_FileOutputStream_write", .desc = "(IZ)V" },
    .{ .method = "Java_java_io_FileOutputStream_writeBytes", .desc = "([BIIZ)V" },
    .{ .method = "Java_java_io_FileOutputStream_initIDs", .desc = "()V" },
};
