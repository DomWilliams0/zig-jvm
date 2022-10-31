const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_vm_VMSupport_initAgentProperties", .desc = "(Ljava/util/Properties;)Ljava/util/Properties;" },
    .{ .method = "Java_jdk_internal_vm_VMSupport_getVMTemporaryDirectory", .desc = "()Ljava/lang/String;" },
};
