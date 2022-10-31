const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_IOUtil_randomBytes", .desc = "([B)Z" },
    .{ .method = "Java_sun_nio_ch_IOUtil_makePipe", .desc = "(Z)J" },
    .{ .method = "Java_sun_nio_ch_IOUtil_write1", .desc = "(IB)I" },
    .{ .method = "Java_sun_nio_ch_IOUtil_drain", .desc = "(I)Z" },
    .{ .method = "Java_sun_nio_ch_IOUtil_drain1", .desc = "(I)I" },
    .{ .method = "Java_sun_nio_ch_IOUtil_configureBlocking", .desc = "(Ljava/io/FileDescriptor;Z)V" },
    .{ .method = "Java_sun_nio_ch_IOUtil_fdVal", .desc = "(Ljava/io/FileDescriptor;)I" },
    .{ .method = "Java_sun_nio_ch_IOUtil_setfdVal", .desc = "(Ljava/io/FileDescriptor;I)V" },
    .{ .method = "Java_sun_nio_ch_IOUtil_fdLimit", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_IOUtil_iovMax", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_IOUtil_writevMax", .desc = "()J" },
    .{ .method = "Java_sun_nio_ch_IOUtil_initIDs", .desc = "()V" },
};
