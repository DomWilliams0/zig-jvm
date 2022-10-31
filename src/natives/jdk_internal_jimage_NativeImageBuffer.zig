const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_jimage_NativeImageBuffer_getNativeMap", .desc = "(Ljava/lang/String;)Ljava/nio/ByteBuffer;" },
};
