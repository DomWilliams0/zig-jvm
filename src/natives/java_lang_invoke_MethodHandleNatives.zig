const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_init", .desc = "(Ljava/lang/invoke/MemberName;Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_expand", .desc = "(Ljava/lang/invoke/MemberName;)V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_resolve", .desc = "(Ljava/lang/invoke/MemberName;Ljava/lang/Class;IZ)Ljava/lang/invoke/MemberName;" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_getMembers", .desc = "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/String;ILjava/lang/Class;I[Ljava/lang/invoke/MemberName;)I" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_objectFieldOffset", .desc = "(Ljava/lang/invoke/MemberName;)J" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_staticFieldOffset", .desc = "(Ljava/lang/invoke/MemberName;)J" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_staticFieldBase", .desc = "(Ljava/lang/invoke/MemberName;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_getMemberVMInfo", .desc = "(Ljava/lang/invoke/MemberName;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_setCallSiteTargetNormal", .desc = "(Ljava/lang/invoke/CallSite;Ljava/lang/invoke/MethodHandle;)V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_setCallSiteTargetVolatile", .desc = "(Ljava/lang/invoke/CallSite;Ljava/lang/invoke/MethodHandle;)V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_copyOutBootstrapArguments", .desc = "(Ljava/lang/Class;[III[Ljava/lang/Object;IZLjava/lang/Object;)V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_clearCallSiteContext", .desc = "(Ljava/lang/invoke/MethodHandleNatives$CallSiteContext;)V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_registerNatives", .desc = "()V" },
    .{ .method = "Java_java_lang_invoke_MethodHandleNatives_getNamedCon", .desc = "(I[Ljava/lang/Object;)I" },
};
