const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;

pub export fn Java_jdk_internal_util_SystemProps_00024Raw_platformProperties(raw_env: jni.JniEnvPtr) sys.jobjectArray {
    const env = jni.convert(raw_env);

    // TODO check native indices vs class indices
    const alloc = jvm.state.thread_state().global.allocator.inner;
    const props = jvm.properties.PlatformProperties.fetch(alloc) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
    defer props.deinit(alloc);

    const props_array = props.toArray();

    const java_lang_String = env.FindClass(raw_env, "java/lang/String") orelse return null;
    const array = env.NewObjectArray(raw_env, props_array.len, java_lang_String, null) orelse return null;

    for (props_array) |s, i|
        if (s) |value| {
            const string = env.NewStringUTF(raw_env, value.ptr) orelse return null;
            env.SetObjectArrayElement(raw_env, array, @intCast(c_int, i), @ptrCast(sys.jobject, string));
            std.debug.assert(env.ExceptionCheck(raw_env) == sys.JNI_FALSE); // should not fail
        };

    return array;
}

pub export fn Java_jdk_internal_util_SystemProps_00024Raw_vmProperties(raw_env: jni.JniEnvPtr) sys.jobjectArray {
    const env = jni.convert(raw_env);

    const props = jvm.properties.SystemProperties.fetch(jvm.state.thread_state().global.args);
    const kvs = props.keyValues();

    const java_lang_String = env.FindClass(raw_env, "java/lang/String") orelse return null;
    const array = env.NewObjectArray(raw_env, kvs.len * 2, java_lang_String, null) orelse return null;

    for (kvs) |kv, i| {
        std.log.debug("vmProperty[{s}] = \"{any}\"", .{ kv[0], std.fmt.fmtSliceEscapeLower(kv[1]) });
        const key = env.NewStringUTF(raw_env, kv[0].ptr) orelse return null;
        const val = env.NewStringUTF(raw_env, kv[1].ptr) orelse return null;
        env.SetObjectArrayElement(raw_env, array, @intCast(c_int, i * 2), @ptrCast(sys.jobject, key));
        std.debug.assert(env.ExceptionCheck(raw_env) == sys.JNI_FALSE); // should not fail
        env.SetObjectArrayElement(raw_env, array, @intCast(c_int, (i * 2) + 1), @ptrCast(sys.jobject, val));
        std.debug.assert(env.ExceptionCheck(raw_env) == sys.JNI_FALSE); // should not fail
    }

    return array;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_util_SystemProps_00024Raw_vmProperties", .desc = "()[Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_util_SystemProps_00024Raw_platformProperties", .desc = "()[Ljava/lang/String;" },
};
