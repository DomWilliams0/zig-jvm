const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_UnixDomainSockets_localAddress0", .desc = "(Ljava/io/FileDescriptor;)[B" },
    .{ .method = "Java_sun_nio_ch_UnixDomainSockets_init", .desc = "()Z" },
    .{ .method = "Java_sun_nio_ch_UnixDomainSockets_socket0", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_UnixDomainSockets_bind0", .desc = "(Ljava/io/FileDescriptor;[B)V" },
    .{ .method = "Java_sun_nio_ch_UnixDomainSockets_connect0", .desc = "(Ljava/io/FileDescriptor;[B)I" },
    .{ .method = "Java_sun_nio_ch_UnixDomainSockets_accept0", .desc = "(Ljava/io/FileDescriptor;Ljava/io/FileDescriptor;[Ljava/lang/Object;)I" },
};
