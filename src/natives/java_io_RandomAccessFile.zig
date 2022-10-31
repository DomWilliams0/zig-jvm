const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_RandomAccessFile_open0", .desc = "(Ljava/lang/String;I)V" },
    .{ .method = "Java_java_io_RandomAccessFile_read0", .desc = "()I" },
    .{ .method = "Java_java_io_RandomAccessFile_readBytes", .desc = "([BII)I" },
    .{ .method = "Java_java_io_RandomAccessFile_write0", .desc = "(I)V" },
    .{ .method = "Java_java_io_RandomAccessFile_writeBytes", .desc = "([BII)V" },
    .{ .method = "Java_java_io_RandomAccessFile_getFilePointer", .desc = "()J" },
    .{ .method = "Java_java_io_RandomAccessFile_seek0", .desc = "(J)V" },
    .{ .method = "Java_java_io_RandomAccessFile_length", .desc = "()J" },
    .{ .method = "Java_java_io_RandomAccessFile_setLength", .desc = "(J)V" },
    .{ .method = "Java_java_io_RandomAccessFile_initIDs", .desc = "()V" },
};
