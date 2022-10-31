const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_StrictMath_sin", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_cos", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_tan", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_asin", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_acos", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_atan", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_log", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_log10", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_sqrt", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_IEEEremainder", .desc = "(DD)D" },
    .{ .method = "Java_java_lang_StrictMath_atan2", .desc = "(DD)D" },
    .{ .method = "Java_java_lang_StrictMath_sinh", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_cosh", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_tanh", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_expm1", .desc = "(D)D" },
    .{ .method = "Java_java_lang_StrictMath_log1p", .desc = "(D)D" },
};
