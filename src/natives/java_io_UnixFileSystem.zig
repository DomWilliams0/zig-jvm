const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_io_UnixFileSystem_initIDs() void {}

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
