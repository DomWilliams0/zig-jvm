const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_util_concurrent_atomic_AtomicLong_VMSupportsCS8() sys.jboolean {
    return jni.convert(true);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_util_concurrent_atomic_AtomicLong_VMSupportsCS8", .desc = "()Z" },
};
