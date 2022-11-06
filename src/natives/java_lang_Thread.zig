const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_Thread_registerNatives() void {}

pub export fn Java_java_lang_Thread_currentThread() sys.jobject {
    const t = jvm.state.thread_state();
    const obj = t.thread_obj.clone();
    return jni.convert(obj);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Thread_registerNatives", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_currentThread", .desc = "()Ljava/lang/Thread;" },
    .{ .method = "Java_java_lang_Thread_yield", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_sleep", .desc = "(J)V" },
    .{ .method = "Java_java_lang_Thread_start0", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_isAlive", .desc = "()Z" },
    .{ .method = "Java_java_lang_Thread_holdsLock", .desc = "(Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_Thread_dumpThreads", .desc = "([Ljava/lang/Thread;)[[Ljava/lang/StackTraceElement;" },
    .{ .method = "Java_java_lang_Thread_getThreads", .desc = "()[Ljava/lang/Thread;" },
    .{ .method = "Java_java_lang_Thread_setPriority0", .desc = "(I)V" },
    .{ .method = "Java_java_lang_Thread_stop0", .desc = "(Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_Thread_suspend0", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_resume0", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_interrupt0", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_clearInterruptEvent", .desc = "()V" },
    .{ .method = "Java_java_lang_Thread_setNativeName", .desc = "(Ljava/lang/String;)V" },
};
