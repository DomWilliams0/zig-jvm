const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_String_intern(_: JniEnvPtr, jstring: sys.jstring) sys.jstring {
    // TODO actually intern lmao
    return jstring;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_String_intern", .desc = "()Ljava/lang/String;" },
};
