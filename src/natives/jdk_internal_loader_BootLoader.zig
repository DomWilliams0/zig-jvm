const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_loader_BootLoader_getSystemPackageNames", .desc = "()[Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_loader_BootLoader_getSystemPackageLocation", .desc = "(Ljava/lang/String;)Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_loader_BootLoader_setBootLoaderUnnamedModule0", .desc = "(Ljava/lang/Module;)V" },
};
