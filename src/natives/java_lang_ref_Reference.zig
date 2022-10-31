const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_ref_Reference_getAndClearReferencePendingList", .desc = "()Ljava/lang/ref/Reference;" },
    .{ .method = "Java_java_lang_ref_Reference_hasReferencePendingList", .desc = "()Z" },
    .{ .method = "Java_java_lang_ref_Reference_waitForReferencePendingList", .desc = "()V" },
    .{ .method = "Java_java_lang_ref_Reference_refersTo0", .desc = "(Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_ref_Reference_clear0", .desc = "()V" },
};
