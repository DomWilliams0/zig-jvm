const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_util_zip_Adler32_update", .desc = "(II)I" },
    .{ .method = "Java_java_util_zip_Adler32_updateBytes", .desc = "(I[BII)I" },
    .{ .method = "Java_java_util_zip_Adler32_updateByteBuffer", .desc = "(IJII)I" },
};
