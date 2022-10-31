const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_DatagramDispatcher_read0", .desc = "(Ljava/io/FileDescriptor;JI)I" },
    .{ .method = "Java_sun_nio_ch_DatagramDispatcher_readv0", .desc = "(Ljava/io/FileDescriptor;JI)J" },
    .{ .method = "Java_sun_nio_ch_DatagramDispatcher_write0", .desc = "(Ljava/io/FileDescriptor;JI)I" },
    .{ .method = "Java_sun_nio_ch_DatagramDispatcher_writev0", .desc = "(Ljava/io/FileDescriptor;JI)J" },
};
