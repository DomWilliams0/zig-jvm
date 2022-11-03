const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_Float_floatToRawIntBits(raw_env: JniEnvPtr, jcls: sys.jclass, float: sys.jfloat) sys.jint {
    _ = jcls;
    _ = raw_env;

    return @bitCast(i32, float);
}

pub export fn Java_java_lang_Float_intBitsToFloat(raw_env: JniEnvPtr, jcls: sys.jclass, int: sys.jint) sys.jfloat {
    _ = jcls;
    _ = raw_env;

    return @bitCast(f32, int);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Float_floatToRawIntBits", .desc = "(F)I" },
    .{ .method = "Java_java_lang_Float_intBitsToFloat", .desc = "(I)F" },
};
