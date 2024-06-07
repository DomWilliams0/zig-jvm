const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_io_UnixFileSystem_initIDs() void {}

pub export fn Java_java_io_UnixFileSystem_canonicalize0(raw_env: JniEnvPtr, fs: sys.jobject, jstring: sys.jstring) sys.jstring {
    _ = fs;

    const thread = jvm.state.thread_state();
    const env = jni.convert(raw_env);

    const path_jstring = jni.convert(jstring).toStrong() orelse {
        const exc = jvm.state.errorToException(error.NullPointer);
        _ = env.Throw(raw_env, jni.convert(exc));
        return null;
    };

    const path_utf8 = path_jstring.get().getStringValueUtf8(thread.global.allocator.inner) catch |e| {
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    } orelse unreachable; // definitely a string
    defer thread.global.allocator.inner.free(path_utf8);

    var path_buf: [std.fs.MAX_PATH_BYTES + 1:0]u8 = undefined;
    const path_abs = std.fs.realpath(path_utf8, &path_buf) catch |e| {
        // TODO build proper error with the reason
        std.log.warn("realpath error: {}", .{e});
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(error.Internal)));
        return null;
    };

    return env.NewStringUTF(raw_env, path_abs.ptr) orelse return null;
}

// from Filesystem.java
// @Native public static final int BA_EXISTS    = 0x01;
// @Native public static final int BA_REGULAR   = 0x02;
// @Native public static final int BA_DIRECTORY = 0x04;
// @Native public static final int BA_HIDDEN    = 0x08;
const BooleanAttrs = enum(i32) {
    exists = 0x01,
    regular = 0x02,
    directory = 0x04,
    hidden = 0x08,
};

/// Allocated from global allocator
fn pathFromFile(thread: *jvm.state.ThreadEnv, jfile: sys.jobject) ![:0]u8 {
    const file_obj = jni.convert(jfile).toStrong() orelse return error.NullPointer;

    // TODO cache this
    const file_cls = try thread.global.classloader.loadClass("java/io/File", .bootstrap);
    const path_field = (file_cls.get().findFieldRecursively("path", "Ljava/lang/String;", .{ .static = false }) orelse @panic("missing value path")).id;

    const jpath = file_obj.get().getField(jvm.VmObjectRef.Nullable, path_field).toStrong() orelse return error.NullPointer;
    const str = try jpath.get().getStringValueUtf8(thread.global.allocator.inner);
    return str orelse error.Internal; // should be a string for sure
}

pub export fn Java_java_io_UnixFileSystem_getBooleanAttributes0(raw_env: JniEnvPtr, jfile: sys.jobject) sys.jint {
    const thread = jvm.state.thread_state();
    const env = jni.convert(raw_env);
    const path_utf8 = pathFromFile(thread, jfile) catch |e| {
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return 0;
    };
    defer thread.global.allocator.inner.free(path_utf8);

    std.log.debug("file path {s}", .{path_utf8});

    const handle = std.fs.openFileAbsoluteZ(path_utf8, .{ .mode = .read_only }) catch |e| switch (e) {
        error.FileNotFound => {
            // return successfully with no flags set
            return 0;
        },
        else => {
            std.log.warn("TODO pass io error to exception: {}", .{e});
            _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(error.Internal))); // TODO io error
            return 0;
        },
    };
    defer handle.close();

    const metadata = handle.metadata() catch |e| {
        std.log.warn("TODO pass io error to exception: {}", .{e});
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(error.Internal))); // TODO io error
        return 0;
    };

    // File instance should have opened an open file
    var ret: i32 = @intFromEnum(BooleanAttrs.exists);
    switch (metadata.kind()) {
        .file => ret |= @intFromEnum(BooleanAttrs.regular),
        .directory => ret |= @intFromEnum(BooleanAttrs.directory),
        else => {},
    }

    return ret;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_io_UnixFileSystem_canonicalize0", .desc = "(Ljava/lang/String;)Ljava/lang/String;" },
    .{ .method = "Java_java_io_UnixFileSystem_getBooleanAttributes0", .desc = "(Ljava/io/File;)I" },
    .{ .method = "Java_java_io_UnixFileSystem_checkAccess", .desc = "(Ljava/io/File;I)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_getLastModifiedTime", .desc = "(Ljava/io/File;)J" },
    .{ .method = "Java_java_io_UnixFileSystem_getLength", .desc = "(Ljava/io/File;)J" },
    .{ .method = "Java_java_io_UnixFileSystem_setPermission", .desc = "(Ljava/io/File;IZZ)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_createFileExclusively", .desc = "(Ljava/lang/String;)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_delete0", .desc = "(Ljava/io/File;)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_list", .desc = "(Ljava/io/File;)[Ljava/lang/String;" },
    .{ .method = "Java_java_io_UnixFileSystem_createDirectory", .desc = "(Ljava/io/File;)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_rename0", .desc = "(Ljava/io/File;Ljava/io/File;)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_setLastModifiedTime", .desc = "(Ljava/io/File;J)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_setReadOnly", .desc = "(Ljava/io/File;)Z" },
    .{ .method = "Java_java_io_UnixFileSystem_getSpace", .desc = "(Ljava/io/File;I)J" },
    .{ .method = "Java_java_io_UnixFileSystem_getNameMax0", .desc = "(Ljava/lang/String;)J" },
    .{ .method = "Java_java_io_UnixFileSystem_initIDs", .desc = "()V" },
};
