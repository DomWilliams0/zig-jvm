const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Module_defineModule0", .desc = "(Ljava/lang/Module;ZLjava/lang/String;Ljava/lang/String;[Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_Module_addReads0", .desc = "(Ljava/lang/Module;Ljava/lang/Module;)V" },
    .{ .method = "Java_java_lang_Module_addExports0", .desc = "(Ljava/lang/Module;Ljava/lang/String;Ljava/lang/Module;)V" },
    .{ .method = "Java_java_lang_Module_addExportsToAll0", .desc = "(Ljava/lang/Module;Ljava/lang/String;)V" },
    .{ .method = "Java_java_lang_Module_addExportsToAllUnnamed0", .desc = "(Ljava/lang/Module;Ljava/lang/String;)V" },
};
