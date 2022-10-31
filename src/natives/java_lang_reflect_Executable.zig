const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_reflect_Executable_getParameters0", .desc = "()[Ljava/lang/reflect/Parameter;" },
    .{ .method = "Java_java_lang_reflect_Executable_getTypeAnnotationBytes0", .desc = "()[B" },
};
