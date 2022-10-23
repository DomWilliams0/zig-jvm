const std = @import("std");
const sys = @import("jvm").sys;

pub export fn Java_java_lang_Throwable_fillInStackTrace(_: *anyopaque, this: sys.jobject) sys.jobject {
    std.log.warn("TODO fill in stack trace", .{});
    return this;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Throwable_fillInStackTrace", .desc = "(I)Ljava/lang/Throwable;" },
};
