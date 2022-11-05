const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_Runtime_maxMemory() sys.jlong {
    // TODO actual limit
    return jni.convert(@as(i64, 1024 * 1024 * 1024)); // 1gb
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Runtime_availableProcessors", .desc = "()I" },
    .{ .method = "Java_java_lang_Runtime_freeMemory", .desc = "()J" },
    .{ .method = "Java_java_lang_Runtime_totalMemory", .desc = "()J" },
    .{ .method = "Java_java_lang_Runtime_maxMemory", .desc = "()J" },
    .{ .method = "Java_java_lang_Runtime_gc", .desc = "()V" },
};
