const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_EventFD_eventfd0", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_EventFD_set0", .desc = "(I)I" },
};
