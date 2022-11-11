const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_io_FileDescriptor_initIDs() void {}

pub export fn Java_java_io_FileDescriptor_getHandle(_: JniEnvPtr, _: sys.jclass, fd: sys.jint) sys.jlong {
    if (@import("builtin").os.tag == .windows) @compileError("actually open handles");

    return jni.convert(@intCast(i64, fd));
}

const fcntl = @cImport({
    @cInclude("fcntl.h");
});

pub export fn Java_java_io_FileDescriptor_getAppend(raw_env: JniEnvPtr, _: sys.jclass, fd: sys.jint) sys.jboolean {
    const flags = std.os.fcntl(fd, fcntl.F_GETFL, undefined) catch |e| {
        std.log.warn("fnctl failed: {any}", .{e});
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.Internal)));
        return sys.JNI_FALSE;
    };

    return if ((flags & fcntl.O_APPEND) == 0) sys.JNI_FALSE else sys.JNI_TRUE;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_FileDescriptor_sync", .desc = "()V" },
    .{ .method = "Java_java_io_FileDescriptor_initIDs", .desc = "()V" },
    .{ .method = "Java_java_io_FileDescriptor_getHandle", .desc = "(I)J" },
    .{ .method = "Java_java_io_FileDescriptor_getAppend", .desc = "(I)Z" },
    .{ .method = "Java_java_io_FileDescriptor_close0", .desc = "()V" },
};
