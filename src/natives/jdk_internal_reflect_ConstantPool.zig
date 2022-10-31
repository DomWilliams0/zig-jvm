const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getSize0", .desc = "(Ljava/lang/Object;)I" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getClassAt0", .desc = "(Ljava/lang/Object;I)Ljava/lang/Class;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getClassAtIfLoaded0", .desc = "(Ljava/lang/Object;I)Ljava/lang/Class;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getClassRefIndexAt0", .desc = "(Ljava/lang/Object;I)I" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getMethodAt0", .desc = "(Ljava/lang/Object;I)Ljava/lang/reflect/Member;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getMethodAtIfLoaded0", .desc = "(Ljava/lang/Object;I)Ljava/lang/reflect/Member;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getFieldAt0", .desc = "(Ljava/lang/Object;I)Ljava/lang/reflect/Field;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getFieldAtIfLoaded0", .desc = "(Ljava/lang/Object;I)Ljava/lang/reflect/Field;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getMemberRefInfoAt0", .desc = "(Ljava/lang/Object;I)[Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getNameAndTypeRefIndexAt0", .desc = "(Ljava/lang/Object;I)I" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getNameAndTypeRefInfoAt0", .desc = "(Ljava/lang/Object;I)[Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getIntAt0", .desc = "(Ljava/lang/Object;I)I" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getLongAt0", .desc = "(Ljava/lang/Object;I)J" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getFloatAt0", .desc = "(Ljava/lang/Object;I)F" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getDoubleAt0", .desc = "(Ljava/lang/Object;I)D" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getStringAt0", .desc = "(Ljava/lang/Object;I)Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getUTF8At0", .desc = "(Ljava/lang/Object;I)Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_reflect_ConstantPool_getTagAt0", .desc = "(Ljava/lang/Object;I)B" },
};
