const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_util_zip_Inflater_initIDs", .desc = "()V" },
    .{ .method = "Java_java_util_zip_Inflater_init", .desc = "(Z)J" },
    .{ .method = "Java_java_util_zip_Inflater_setDictionary", .desc = "(J[BII)V" },
    .{ .method = "Java_java_util_zip_Inflater_setDictionaryBuffer", .desc = "(JJI)V" },
    .{ .method = "Java_java_util_zip_Inflater_inflateBytesBytes", .desc = "(J[BII[BII)J" },
    .{ .method = "Java_java_util_zip_Inflater_inflateBytesBuffer", .desc = "(J[BIIJI)J" },
    .{ .method = "Java_java_util_zip_Inflater_inflateBufferBytes", .desc = "(JJI[BII)J" },
    .{ .method = "Java_java_util_zip_Inflater_inflateBufferBuffer", .desc = "(JJIJI)J" },
    .{ .method = "Java_java_util_zip_Inflater_getAdler", .desc = "(J)I" },
    .{ .method = "Java_java_util_zip_Inflater_reset", .desc = "(J)V" },
    .{ .method = "Java_java_util_zip_Inflater_end", .desc = "(J)V" },
};
