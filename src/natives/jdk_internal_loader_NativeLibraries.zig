const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_loader_NativeLibraries_load", .desc = "(Ljdk/internal/loader/NativeLibraries$NativeLibraryImpl;Ljava/lang/String;ZZZ)Z" },
    .{ .method = "Java_jdk_internal_loader_NativeLibraries_unload", .desc = "(Ljava/lang/String;ZZJ)V" },
    .{ .method = "Java_jdk_internal_loader_NativeLibraries_findBuiltinLib", .desc = "(Ljava/lang/String;)Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_loader_NativeLibraries_findEntry0", .desc = "(Ljdk/internal/loader/NativeLibraries$NativeLibraryImpl;Ljava/lang/String;)J" },
};
