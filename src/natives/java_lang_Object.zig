const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;

pub export fn Java_java_lang_Object_getClass(raw_env: jni.JniEnvPtr, this: sys.jobject) sys.jclass {
    _ = raw_env;
    const obj = jni.convert(this).toStrongUnchecked(); // `this` can't be null
    return jni.convert(obj.get().class);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Object_getClass", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Object_hashCode", .desc = "()I" },
    .{ .method = "Java_java_lang_Object_clone", .desc = "()Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_Object_notify", .desc = "()V" },
    .{ .method = "Java_java_lang_Object_notifyAll", .desc = "()V" },
    .{ .method = "Java_java_lang_Object_wait", .desc = "(J)V" },
};
