const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_FileChannelImpl_map0", .desc = "(IJJZ)J" },
    .{ .method = "Java_sun_nio_ch_FileChannelImpl_unmap0", .desc = "(JJ)I" },
    .{ .method = "Java_sun_nio_ch_FileChannelImpl_transferTo0", .desc = "(Ljava/io/FileDescriptor;JJLjava/io/FileDescriptor;)J" },
    .{ .method = "Java_sun_nio_ch_FileChannelImpl_maxDirectTransferSize0", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_FileChannelImpl_initIDs", .desc = "()J" },
};
