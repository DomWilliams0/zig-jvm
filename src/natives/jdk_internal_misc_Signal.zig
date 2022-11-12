const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_jdk_internal_misc_Signal_findSignal0(raw_env: jni.JniEnvPtr, _: sys.jclass, name: sys.jstring) sys.jint {
    const env = jni.convert(raw_env);
    const str_c = env.GetStringUTFChars(raw_env, name, null);
    defer env.ReleaseStringUTFChars(raw_env, name, str_c);
    const str = std.mem.span(str_c);

    // TODO get these properly
    const val: i32 = if (std.mem.eql(u8, str, "HUP")) 1 else if (std.mem.eql(u8, str, "INT")) 2 else if (std.mem.eql(u8, str, "TERM")) 15 else blk: {
        std.log.warn("unknown signal '{s}'", .{str});
        break :blk -1;
    };

    return jni.convert(val);
}

pub export fn Java_jdk_internal_misc_Signal_handle0(raw_env: jni.JniEnvPtr, _: sys.jclass, signal: sys.jint, handler: sys.jlong) sys.jlong {
    _ = handler;
    _ = signal;
    _ = raw_env;
    // TODO actually set signal handler
    return 0;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_misc_Signal_findSignal0", .desc = "(Ljava/lang/String;)I" },
    .{ .method = "Java_jdk_internal_misc_Signal_handle0", .desc = "(IJ)J" },
    .{ .method = "Java_jdk_internal_misc_Signal_raise0", .desc = "(I)V" },
};
