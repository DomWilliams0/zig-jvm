const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_NullPointerException_getExtendedNPEMessage(raw_env: JniEnvPtr) sys.jobject {
    const t = jvm.state.thread_state();

    // TODO find the right exception, then find its source and use that instead
    const this_frame = t.interpreter.top_frame.?;
    const npe_frame = this_frame.parent_frame orelse return null;
    const f = npe_frame.parent_frame orelse return null;
    var pc_buf: [8]u8 = undefined;
    const pc = if (f.currentPc()) |pc|
        std.fmt.bufPrint(&pc_buf, " pc={d}", .{pc}) catch ""
    else
        "";

    const utf = std.fmt.allocPrint(t.global.allocator.inner, "not really useful but anyway: {?}{s}", .{ f.method, pc }) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
    defer t.global.allocator.inner.free(utf);

    const string = t.global.string_pool.getString(utf) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
    return jni.convert(string);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_NullPointerException_getExtendedNPEMessage", .desc = "()Ljava/lang/String;" },
};
