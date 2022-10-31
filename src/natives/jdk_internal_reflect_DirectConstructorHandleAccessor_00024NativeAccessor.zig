const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_reflect_DirectConstructorHandleAccessor_00024NativeAccessor_newInstance0", .desc = "(Ljava/lang/reflect/Constructor;[Ljava/lang/Object;)Ljava/lang/Object;" },
};
