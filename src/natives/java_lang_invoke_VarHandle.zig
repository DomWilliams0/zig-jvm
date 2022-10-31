const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_invoke_VarHandle_get", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_set", .desc = "([Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getVolatile", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_setVolatile", .desc = "([Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getOpaque", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_setOpaque", .desc = "([Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_setRelease", .desc = "([Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_invoke_VarHandle_compareAndSet", .desc = "([Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_invoke_VarHandle_compareAndExchange", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_compareAndExchangeAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_compareAndExchangeRelease", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_weakCompareAndSetPlain", .desc = "([Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_invoke_VarHandle_weakCompareAndSet", .desc = "([Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_invoke_VarHandle_weakCompareAndSetAcquire", .desc = "([Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_invoke_VarHandle_weakCompareAndSetRelease", .desc = "([Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndSet", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndSetAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndSetRelease", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndAdd", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndAddAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndAddRelease", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseOr", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseOrAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseOrRelease", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseAnd", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseAndAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseAndRelease", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseXor", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseXorAcquire", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_invoke_VarHandle_getAndBitwiseXorRelease", .desc = "([Ljava/lang/Object;)Ljava/lang/Object;" },
};
