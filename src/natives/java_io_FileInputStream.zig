const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_io_FileInputStream_initIDs() void {}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_FileInputStream_open0", .desc = "(Ljava/lang/String;)V" },
    .{ .method = "Java_java_io_FileInputStream_read0", .desc = "()I" },
    .{ .method = "Java_java_io_FileInputStream_readBytes", .desc = "([BII)I" },
    .{ .method = "Java_java_io_FileInputStream_length0", .desc = "()J" },
    .{ .method = "Java_java_io_FileInputStream_position0", .desc = "()J" },
    .{ .method = "Java_java_io_FileInputStream_skip0", .desc = "(J)J" },
    .{ .method = "Java_java_io_FileInputStream_available0", .desc = "()I" },
    .{ .method = "Java_java_io_FileInputStream_initIDs", .desc = "()V" },
};
