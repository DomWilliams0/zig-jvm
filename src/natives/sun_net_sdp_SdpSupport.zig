const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_net_sdp_SdpSupport_create0", .desc = "()I" },
    .{ .method = "Java_sun_net_sdp_SdpSupport_convert0", .desc = "(I)V" },
};
