const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_net_NetworkInterface_getAll", .desc = "()[Ljava/net/NetworkInterface;" },
    .{ .method = "Java_java_net_NetworkInterface_getByName0", .desc = "(Ljava/lang/String;)Ljava/net/NetworkInterface;" },
    .{ .method = "Java_java_net_NetworkInterface_getByIndex0", .desc = "(I)Ljava/net/NetworkInterface;" },
    .{ .method = "Java_java_net_NetworkInterface_boundInetAddress0", .desc = "(Ljava/net/InetAddress;)Z" },
    .{ .method = "Java_java_net_NetworkInterface_getByInetAddress0", .desc = "(Ljava/net/InetAddress;)Ljava/net/NetworkInterface;" },
    .{ .method = "Java_java_net_NetworkInterface_isUp0", .desc = "(Ljava/lang/String;I)Z" },
    .{ .method = "Java_java_net_NetworkInterface_isLoopback0", .desc = "(Ljava/lang/String;I)Z" },
    .{ .method = "Java_java_net_NetworkInterface_supportsMulticast0", .desc = "(Ljava/lang/String;I)Z" },
    .{ .method = "Java_java_net_NetworkInterface_isP2P0", .desc = "(Ljava/lang/String;I)Z" },
    .{ .method = "Java_java_net_NetworkInterface_getMacAddr0", .desc = "([BLjava/lang/String;I)[B" },
    .{ .method = "Java_java_net_NetworkInterface_getMTU0", .desc = "(Ljava/lang/String;I)I" },
    .{ .method = "Java_java_net_NetworkInterface_init", .desc = "()V" },
};
