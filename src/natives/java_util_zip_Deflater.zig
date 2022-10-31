const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_util_zip_Deflater_init", .desc = "(IIZ)J" },
    .{ .method = "Java_java_util_zip_Deflater_setDictionary", .desc = "(J[BII)V" },
    .{ .method = "Java_java_util_zip_Deflater_setDictionaryBuffer", .desc = "(JJI)V" },
    .{ .method = "Java_java_util_zip_Deflater_deflateBytesBytes", .desc = "(J[BII[BIIII)J" },
    .{ .method = "Java_java_util_zip_Deflater_deflateBytesBuffer", .desc = "(J[BIIJIII)J" },
    .{ .method = "Java_java_util_zip_Deflater_deflateBufferBytes", .desc = "(JJI[BIIII)J" },
    .{ .method = "Java_java_util_zip_Deflater_deflateBufferBuffer", .desc = "(JJIJIII)J" },
    .{ .method = "Java_java_util_zip_Deflater_getAdler", .desc = "(J)I" },
    .{ .method = "Java_java_util_zip_Deflater_reset", .desc = "(J)V" },
    .{ .method = "Java_java_util_zip_Deflater_end", .desc = "(J)V" },
};
