const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Float_floatToRawIntBits", .desc = "(F)I" },
    .{ .method = "Java_java_lang_Float_intBitsToFloat", .desc = "(I)F" },
};
