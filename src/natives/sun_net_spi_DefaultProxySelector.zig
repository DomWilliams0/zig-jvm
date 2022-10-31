const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_net_spi_DefaultProxySelector_init", .desc = "()Z" },
    .{ .method = "Java_sun_net_spi_DefaultProxySelector_getSystemProxies", .desc = "(Ljava/lang/String;Ljava/lang/String;)[Ljava/net/Proxy;" },
};
