const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_vm_vector_VectorSupport_getMaxLaneCount", .desc = "(Ljava/lang/Class;)I" },
    .{ .method = "Java_jdk_internal_vm_vector_VectorSupport_registerNatives", .desc = "()I" },
};
