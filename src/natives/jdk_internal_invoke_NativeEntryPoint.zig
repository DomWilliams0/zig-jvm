const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_invoke_NativeEntryPoint_vmStorageToVMReg", .desc = "(II)J" },
    .{ .method = "Java_jdk_internal_invoke_NativeEntryPoint_registerNatives", .desc = "()V" },
};
