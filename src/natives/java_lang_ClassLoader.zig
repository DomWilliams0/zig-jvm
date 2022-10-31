const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_ClassLoader_registerNatives", .desc = "()V" },
    .{ .method = "Java_java_lang_ClassLoader_defineClass1", .desc = "(Ljava/lang/ClassLoader;Ljava/lang/String;[BIILjava/security/ProtectionDomain;Ljava/lang/String;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_ClassLoader_defineClass2", .desc = "(Ljava/lang/ClassLoader;Ljava/lang/String;Ljava/nio/ByteBuffer;IILjava/security/ProtectionDomain;Ljava/lang/String;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_ClassLoader_defineClass0", .desc = "(Ljava/lang/ClassLoader;Ljava/lang/Class;Ljava/lang/String;[BIILjava/security/ProtectionDomain;ZILjava/lang/Object;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_ClassLoader_findBootstrapClass", .desc = "(Ljava/lang/String;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_ClassLoader_findLoadedClass0", .desc = "(Ljava/lang/String;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_ClassLoader_retrieveDirectives", .desc = "()Ljava/lang/AssertionStatusDirectives;" },
};
