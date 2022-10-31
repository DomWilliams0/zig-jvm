const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_net_Inet6AddressImpl_getLocalHostName", .desc = "()Ljava/lang/String;" },
    .{ .method = "Java_java_net_Inet6AddressImpl_lookupAllHostAddr", .desc = "(Ljava/lang/String;I)[Ljava/net/InetAddress;" },
    .{ .method = "Java_java_net_Inet6AddressImpl_getHostByAddr", .desc = "([B)Ljava/lang/String;" },
    .{ .method = "Java_java_net_Inet6AddressImpl_isReachable0", .desc = "([BII[BII)Z" },
};
