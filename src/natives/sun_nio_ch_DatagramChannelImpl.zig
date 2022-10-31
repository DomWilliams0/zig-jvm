const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_DatagramChannelImpl_disconnect0", .desc = "(Ljava/io/FileDescriptor;Z)V" },
    .{ .method = "Java_sun_nio_ch_DatagramChannelImpl_receive0", .desc = "(Ljava/io/FileDescriptor;JIJZ)I" },
    .{ .method = "Java_sun_nio_ch_DatagramChannelImpl_send0", .desc = "(Ljava/io/FileDescriptor;JIJI)I" },
};
