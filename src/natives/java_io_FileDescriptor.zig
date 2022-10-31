const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_FileDescriptor_sync", .desc = "()V" },
    .{ .method = "Java_java_io_FileDescriptor_initIDs", .desc = "()V" },
    .{ .method = "Java_java_io_FileDescriptor_getHandle", .desc = "(I)J" },
    .{ .method = "Java_java_io_FileDescriptor_getAppend", .desc = "(I)Z" },
    .{ .method = "Java_java_io_FileDescriptor_close0", .desc = "()V" },
};
