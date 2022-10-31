const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_EPoll_eventSize", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_EPoll_eventsOffset", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_EPoll_dataOffset", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_EPoll_create", .desc = "()I" },
    .{ .method = "Java_sun_nio_ch_EPoll_ctl", .desc = "(IIII)I" },
    .{ .method = "Java_sun_nio_ch_EPoll_wait", .desc = "(IJII)I" },
};
