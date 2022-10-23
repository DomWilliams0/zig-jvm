const std = @import("std");
const jvm = @import("jvm");
const sys = jvm.sys;

pub export fn Java_java_lang_Object_getClass(raw_env: sys.api.JniEnvPtr, this: sys.jobject) sys.jclass {
    _ = raw_env;
    const obj = sys.convert(sys.jobject).from(this).toStrongUnchecked(); // `this` can't be null
    const class = obj.get().class.get().getClassInstance().clone();
    return sys.convert(sys.jobject).to(class.intoNullable());
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Object_getClass", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Object_hashCode", .desc = "()I" },
    .{ .method = "Java_java_lang_Object_clone", .desc = "()Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_Object_notify", .desc = "()V" },
    .{ .method = "Java_java_lang_Object_notifyAll", .desc = "()V" },
    .{ .method = "Java_java_lang_Object_wait", .desc = "(J)V" },
};
