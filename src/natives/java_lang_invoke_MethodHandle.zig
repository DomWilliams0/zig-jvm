const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_invoke_MethodHandle_invokeExact", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_invoke", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_invokeBasic", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_linkToVirtual", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_linkToStatic", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_linkToSpecial", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_linkToInterface", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandle_linkToNative", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
};
