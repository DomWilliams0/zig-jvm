const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_Double_doubleToRawLongBits(raw_env: JniEnvPtr, jcls: sys.jclass, double: sys.jdouble) sys.jlong {
    _ = jcls;
    _ = raw_env;

    return @bitCast(double);
}

pub export fn Java_java_lang_Double_longBitsToDouble(raw_env: JniEnvPtr, jcls: sys.jclass, long: sys.jlong) sys.jdouble {
    _ = jcls;
    _ = raw_env;

    return @bitCast(long);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Double_doubleToRawLongBits", .desc = "(D)J" },
    .{ .method = "Java_java_lang_Double_longBitsToDouble", .desc = "(J)D" },
};
