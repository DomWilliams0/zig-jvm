const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_reflect_Reflection_getCallerClass", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_jdk_internal_reflect_Reflection_getClassAccessFlags", .desc = "(Ljava/lang/Class;)I" },
    .{ .method = "Java_jdk_internal_reflect_Reflection_areNestMates", .desc = "(Ljava/lang/Class;Ljava/lang/Class;)Z" },
};
