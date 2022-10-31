const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_ObjectStreamClass_initNative", .desc = "()V" },
    .{ .method = "Java_java_io_ObjectStreamClass_hasStaticInitializer", .desc = "(Ljava/lang/Class;)Z" },
};
