const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_read0", .desc = "(Ljava/io/FileDescriptor;JI)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_pread0", .desc = "(Ljava/io/FileDescriptor;JIJ)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_readv0", .desc = "(Ljava/io/FileDescriptor;JI)J" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_write0", .desc = "(Ljava/io/FileDescriptor;JI)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_pwrite0", .desc = "(Ljava/io/FileDescriptor;JIJ)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_writev0", .desc = "(Ljava/io/FileDescriptor;JI)J" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_force0", .desc = "(Ljava/io/FileDescriptor;Z)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_seek0", .desc = "(Ljava/io/FileDescriptor;J)J" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_truncate0", .desc = "(Ljava/io/FileDescriptor;J)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_size0", .desc = "(Ljava/io/FileDescriptor;)J" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_lock0", .desc = "(Ljava/io/FileDescriptor;ZJJZ)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_release0", .desc = "(Ljava/io/FileDescriptor;JJ)V" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_close0", .desc = "(Ljava/io/FileDescriptor;)V" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_preClose0", .desc = "(Ljava/io/FileDescriptor;)V" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_dup0", .desc = "(Ljava/io/FileDescriptor;Ljava/io/FileDescriptor;)V" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_closeIntFD", .desc = "(I)V" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_canTransferToFromOverlappedMap0", .desc = "()Z" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_setDirect0", .desc = "(Ljava/io/FileDescriptor;)I" },
    .{ .method = "Java_sun_nio_ch_FileDispatcherImpl_init", .desc = "()V" },
};
