const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_reflect_Array_getLength", .desc = "(Ljava/lang/Object;)I" },
    .{ .method = "Java_java_lang_reflect_Array_get", .desc = "(Ljava/lang/Object;I)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_reflect_Array_getBoolean", .desc = "(Ljava/lang/Object;I)Z" },
    .{ .method = "Java_java_lang_reflect_Array_getByte", .desc = "(Ljava/lang/Object;I)B" },
    .{ .method = "Java_java_lang_reflect_Array_getChar", .desc = "(Ljava/lang/Object;I)C" },
    .{ .method = "Java_java_lang_reflect_Array_getShort", .desc = "(Ljava/lang/Object;I)S" },
    .{ .method = "Java_java_lang_reflect_Array_getInt", .desc = "(Ljava/lang/Object;I)I" },
    .{ .method = "Java_java_lang_reflect_Array_getLong", .desc = "(Ljava/lang/Object;I)J" },
    .{ .method = "Java_java_lang_reflect_Array_getFloat", .desc = "(Ljava/lang/Object;I)F" },
    .{ .method = "Java_java_lang_reflect_Array_getDouble", .desc = "(Ljava/lang/Object;I)D" },
    .{ .method = "Java_java_lang_reflect_Array_set", .desc = "(Ljava/lang/Object;ILjava/lang/Object;)V" },
    .{ .method = "Java_java_lang_reflect_Array_setBoolean", .desc = "(Ljava/lang/Object;IZ)V" },
    .{ .method = "Java_java_lang_reflect_Array_setByte", .desc = "(Ljava/lang/Object;IB)V" },
    .{ .method = "Java_java_lang_reflect_Array_setChar", .desc = "(Ljava/lang/Object;IC)V" },
    .{ .method = "Java_java_lang_reflect_Array_setShort", .desc = "(Ljava/lang/Object;IS)V" },
    .{ .method = "Java_java_lang_reflect_Array_setInt", .desc = "(Ljava/lang/Object;II)V" },
    .{ .method = "Java_java_lang_reflect_Array_setLong", .desc = "(Ljava/lang/Object;IJ)V" },
    .{ .method = "Java_java_lang_reflect_Array_setFloat", .desc = "(Ljava/lang/Object;IF)V" },
    .{ .method = "Java_java_lang_reflect_Array_setDouble", .desc = "(Ljava/lang/Object;ID)V" },
    .{ .method = "Java_java_lang_reflect_Array_newArray", .desc = "(Ljava/lang/Class;I)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_reflect_Array_multiNewArray", .desc = "(Ljava/lang/Class;[I)Ljava/lang/Object;" },
};
