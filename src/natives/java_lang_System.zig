const std = @import("std");
const jvm = @import("jvm");
const sys = jvm.sys;

pub export fn Java_java_lang_System_registerNatives() void {}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_System_registerNatives", .desc = "()V" },
    .{ .method = "Java_java_lang_System_setIn0", .desc = "(Ljava/io/InputStream;)V" },
    .{ .method = "Java_java_lang_System_setOut0", .desc = "(Ljava/io/PrintStream;)V" },
    .{ .method = "Java_java_lang_System_setErr0", .desc = "(Ljava/io/PrintStream;)V" },
    .{ .method = "Java_java_lang_System_currentTimeMillis", .desc = "()J" },
    .{ .method = "Java_java_lang_System_nanoTime", .desc = "()J" },
    .{ .method = "Java_java_lang_System_arraycopy", .desc = "(Ljava/lang/Object;ILjava/lang/Object;II)V" },
    .{ .method = "Java_java_lang_System_identityHashCode", .desc = "(Ljava/lang/Object;)I" },
    .{ .method = "Java_java_lang_System_mapLibraryName", .desc = "(Ljava/lang/String;)Ljava/lang/String;" },
};
