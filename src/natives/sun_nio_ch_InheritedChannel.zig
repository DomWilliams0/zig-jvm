const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_InheritedChannel_initIDs", .desc = "()V" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_dup", .desc = "(I)I" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_dup2", .desc = "(II)V" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_open0", .desc = "(Ljava/lang/String;I)I" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_close0", .desc = "(I)V" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_soType0", .desc = "(I)I" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_addressFamily", .desc = "(I)I" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_inetPeerAddress0", .desc = "(I)Ljava/net/InetAddress;" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_unixPeerAddress0", .desc = "(I)[B" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_peerPort0", .desc = "(I)I" },
    .{ .method = "Java_sun_nio_ch_InheritedChannel_isConnected", .desc = "(I)Z" },
};
