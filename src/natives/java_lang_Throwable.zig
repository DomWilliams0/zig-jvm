const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;

pub export fn Java_java_lang_Throwable_fillInStackTrace(env: *const jni.JniEnv, this: sys.jobject) sys.jobject {
    _ = env;
    const obj = jni.convert(this).toStrong();
    std.log.warn("TODO fill in stack trace on {?}", .{obj});
    return this;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Throwable_fillInStackTrace", .desc = "(I)Ljava/lang/Throwable;" },
};
