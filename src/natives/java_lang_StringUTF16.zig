const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_StringUTF16_isBigEndian() sys.jboolean {
    const is_big = @import("builtin").cpu.arch.endian() == .big;
    return jni.convert(is_big);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_StringUTF16_isBigEndian", .desc = "()Z" },
};
