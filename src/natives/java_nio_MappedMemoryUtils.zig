const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_nio_MappedMemoryUtils_isLoaded0", .desc = "(JJJ)Z" },
    .{ .method = "Java_java_nio_MappedMemoryUtils_load0", .desc = "(JJ)V" },
    .{ .method = "Java_java_nio_MappedMemoryUtils_unload0", .desc = "(JJ)V" },
    .{ .method = "Java_java_nio_MappedMemoryUtils_force0", .desc = "(Ljava/io/FileDescriptor;JJ)V" },
};
