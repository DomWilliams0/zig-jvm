const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_jdk_internal_reflect_Reflection_getCallerClass() sys.jclass {
    const this_frame = jvm.state.thread_state().interpreter.top_frame;
    const caller_frame = this_frame.?.parent_frame orelse @panic("no caller?");

    // TODO ensure caller frame is @CallerSensitive
    const frame = caller_frame.parent_frame;

    // TODO iter and skip java.lang.reflect.Method.invoke()
    while (frame) |f| {
        return jni.convert(f.class);
    }

    @panic("no caller?");
}

pub export fn Java_jdk_internal_reflect_Reflection_getClassAccessFlags(raw_env: jni.JniEnvPtr, _: sys.jclass, jcls: sys.jclass) sys.jint {
    // TODO should take inner classes into account
    const cls = jni.convert(jcls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return 0;
    };

    return jni.convert(@as(i32, @intCast(cls.get().flags.bits)));
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_reflect_Reflection_getCallerClass", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_jdk_internal_reflect_Reflection_getClassAccessFlags", .desc = "(Ljava/lang/Class;)I" },
    .{ .method = "Java_jdk_internal_reflect_Reflection_areNestMates", .desc = "(Ljava/lang/Class;Ljava/lang/Class;)Z" },
};
