const std = @import("std");
const sys = @import("sys");

pub export fn Java_java_lang_Class_registerNatives() void {
}

pub export fn Java_java_lang_Class_desiredAssertionStatus0() sys.jboolean {
    return sys.JNI_FALSE;
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{.method = "Java_java_lang_Class_registerNatives", .desc = "()V"},
    .{.method = "Java_java_lang_Class_desiredAssertionStatus0", .desc = "(Ljava/lang/Class;)Z"},
};