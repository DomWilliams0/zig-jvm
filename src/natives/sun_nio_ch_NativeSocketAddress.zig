const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_AFINET", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_AFINET6", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_sizeofSockAddr4", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_sizeofSockAddr6", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_sizeofFamily", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetFamily", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetSin4Port", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetSin4Addr", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetSin6Port", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetSin6Addr", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetSin6ScopeId", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_NativeSocketAddress_offsetSin6FlowInfo", .desc = "()I" },
};
