const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;

pub export fn Java_jdk_internal_util_SystemProps_00024Raw_platformProperties(raw_env: jni.JniEnvPtr) sys.jobjectArray {
    const env = jni.convert(raw_env);

    // TODO check native indices vs class indices
    const props = jvm.properties.PlatformProperties.fetch(); //catch |e| std.debug.panic("failed to fetch platform properties: {s}", .{e});
    const props_array = props.toArray();

    const java_lang_String = env.FindClass(raw_env, "java/lang/String") orelse return null;
    const array = env.NewObjectArray(raw_env, props_array.len, java_lang_String, null) orelse return null;

    // for (props_array) |s, i|
    //     if (s) |value| {
    //         const string = env.NewStringUTF(raw_env, value) orelse return null;
    //         env.SetObjectArrayElement(raw_env, array, @intCast(c_int, i), string);
    //         std.debug.assert(env.ExceptionCheck(raw_env) == sys.JNI_FALSE); // should not fail
    //     };

    return array;
}

pub export fn Java_jdk_internal_util_SystemProps_00024Raw_vmProperties(raw_env: jni.JniEnvPtr) sys.jobjectArray {
    const env = jni.convert(raw_env);

    const java_lang_String = env.FindClass(raw_env, "java/lang/String") orelse return null;
    const array = env.NewObjectArray(raw_env, 1, java_lang_String, null) orelse return null;
    return array;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_util_SystemProps_00024Raw_vmProperties", .desc = "()[Ljava/lang/String;" },
    .{ .method = "Java_jdk_internal_util_SystemProps_00024Raw_platformProperties", .desc = "()[Ljava/lang/String;" },
};
