const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_security_AccessController_getProtectionDomain", .desc = "(Ljava/lang/Class;)Ljava/security/ProtectionDomain;" },
    .{ .method = "Java_java_security_AccessController_ensureMaterializedForStackWalk", .desc = "(Ljava/lang/Object;)V" },
    .{ .method = "Java_java_security_AccessController_getStackAccessControlContext", .desc = "()Ljava/security/AccessControlContext;" },
    .{ .method = "Java_java_security_AccessController_getInheritedAccessControlContext", .desc = "()Ljava/security/AccessControlContext;" },
};
