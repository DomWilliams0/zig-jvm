const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_getcwd", .desc = "()[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_dup", .desc = "(I)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_open0", .desc = "(JII)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_openat0", .desc = "(IJII)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_close0", .desc = "(I)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_rewind", .desc = "(J)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_getlinelen", .desc = "(J)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_link0", .desc = "(JJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_unlink0", .desc = "(J)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_unlinkat0", .desc = "(IJI)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_mknod0", .desc = "(JIJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_rename0", .desc = "(JJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_renameat0", .desc = "(IJIJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_mkdir0", .desc = "(JI)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_rmdir0", .desc = "(J)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_readlink0", .desc = "(J)[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_realpath0", .desc = "(J)[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_symlink0", .desc = "(JJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_stat0", .desc = "(JLsun/nio/fs/UnixFileAttributes;)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_stat1", .desc = "(J)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_lstat0", .desc = "(JLsun/nio/fs/UnixFileAttributes;)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fstat", .desc = "(ILsun/nio/fs/UnixFileAttributes;)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fstatat0", .desc = "(IJILsun/nio/fs/UnixFileAttributes;)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_chown0", .desc = "(JII)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_lchown0", .desc = "(JII)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fchown", .desc = "(III)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_chmod0", .desc = "(JI)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fchmod", .desc = "(II)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_utimes0", .desc = "(JJJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_futimes", .desc = "(IJJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_futimens", .desc = "(IJJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_lutimes0", .desc = "(JJJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_opendir0", .desc = "(J)J" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fdopendir", .desc = "(I)J" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_closedir", .desc = "(J)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_readdir", .desc = "(J)[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_read", .desc = "(IJI)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_write", .desc = "(IJI)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_access0", .desc = "(JI)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_exists0", .desc = "(J)Z" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_getpwuid", .desc = "(I)[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_getgrgid", .desc = "(I)[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_getpwnam0", .desc = "(J)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_getgrnam0", .desc = "(J)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_statvfs0", .desc = "(JLsun/nio/fs/UnixFileStoreAttributes;)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_strerror", .desc = "(I)[B" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fgetxattr0", .desc = "(IJJI)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fsetxattr0", .desc = "(IJJI)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_fremovexattr0", .desc = "(IJ)V" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_flistxattr", .desc = "(IJI)I" },
    .{ .method = "Java_sun_nio_fs_UnixNativeDispatcher_init", .desc = "()I" },
};
