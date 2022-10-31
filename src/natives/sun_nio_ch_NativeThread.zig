const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_NativeThread_current", .desc = "()J" },
    .{ .method = "Java_sun_nio_ch_NativeThread_signal", .desc = "(J)V" },
    .{ .method = "Java_sun_nio_ch_NativeThread_init", .desc = "()V" },
};
