const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_StackStreamFactory_00024AbstractStackWalker_callStackWalk", .desc = "(JIII[Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_StackStreamFactory_00024AbstractStackWalker_fetchStackFrames", .desc = "(JJII[Ljava/lang/Object;)I" },
};
