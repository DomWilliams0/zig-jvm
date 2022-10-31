const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_misc_CDS_isDumpingClassList0", .desc = "()Z" },
    .{ .method = "Java_jdk_internal_misc_CDS_isDumpingArchive0", .desc = "()Z" },
    .{ .method = "Java_jdk_internal_misc_CDS_isSharingEnabled0", .desc = "()Z" },
    .{ .method = "Java_jdk_internal_misc_CDS_logLambdaFormInvoker", .desc = "(Ljava/lang/String;)V" },
    .{ .method = "Java_jdk_internal_misc_CDS_initializeFromArchive", .desc = "(Ljava/lang/Class;)V" },
    .{ .method = "Java_jdk_internal_misc_CDS_defineArchivedModules", .desc = "(Ljava/lang/ClassLoader;Ljava/lang/ClassLoader;)V" },
    .{ .method = "Java_jdk_internal_misc_CDS_getRandomSeedForDumping", .desc = "()J" },
    .{ .method = "Java_jdk_internal_misc_CDS_dumpClassList", .desc = "(Ljava/lang/String;)V" },
    .{ .method = "Java_jdk_internal_misc_CDS_dumpDynamicArchive", .desc = "(Ljava/lang/String;)V" },
};
