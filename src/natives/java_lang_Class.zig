const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_Class_registerNatives() void {}

pub export fn Java_java_lang_Class_desiredAssertionStatus0() sys.jboolean {
    return sys.JNI_FALSE;
}

fn convertClassName(global: *jvm.state.GlobalState, name: []const u8) jvm.state.Error!jvm.VmObjectRef {
    // copy locally to replace / with .
    const buf = try global.classloader.alloc.dupe(u8, name);
    defer global.classloader.alloc.free(buf);
    std.mem.replaceScalar(u8, buf, '/', '.');

    return try global.string_pool.getString(buf);
}

pub export fn Java_java_lang_Class_initClassName(raw_env: JniEnvPtr, this: sys.jobject) sys.jobject {
    const obj = jni.convert(this).toStrongUnchecked(); // `this` can't be null

    const thread = jvm.state.thread_state();

    const classdata = obj.get().getClassDataUnchecked();
    const name = classdata.get().name;

    const str_obj = convertClassName(thread.global, name) catch |err| {
        const exc = jvm.state.errorToException(err);
        // TODO wew, make this more ergonomic
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(exc));
        return null;
    };

    return jni.convert(str_obj);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_Class_registerNatives", .desc = "()V" },
    .{ .method = "Java_java_lang_Class_forName0", .desc = "(Ljava/lang/String;ZLjava/lang/ClassLoader;Ljava/lang/Class;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_isInstance", .desc = "(Ljava/lang/Object;)Z" },
    .{ .method = "Java_java_lang_Class_isAssignableFrom", .desc = "(Ljava/lang/Class;)Z" },
    .{ .method = "Java_java_lang_Class_isInterface", .desc = "()Z" },
    .{ .method = "Java_java_lang_Class_isArray", .desc = "()Z" },
    .{ .method = "Java_java_lang_Class_isPrimitive", .desc = "()Z" },
    .{ .method = "Java_java_lang_Class_initClassName", .desc = "()Ljava/lang/String;" },
    .{ .method = "Java_java_lang_Class_getSuperclass", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_getInterfaces0", .desc = "()[Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_getModifiers", .desc = "()I" },
    .{ .method = "Java_java_lang_Class_getSigners", .desc = "()[Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_Class_setSigners", .desc = "([Ljava/lang/Object;)V" },
    .{ .method = "Java_java_lang_Class_getEnclosingMethod0", .desc = "()[Ljava/lang/Object;" },
    .{ .method = "Java_java_lang_Class_getDeclaringClass0", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_getSimpleBinaryName0", .desc = "()Ljava/lang/String;" },
    .{ .method = "Java_java_lang_Class_getProtectionDomain0", .desc = "()Ljava/security/ProtectionDomain;" },
    .{ .method = "Java_java_lang_Class_getPrimitiveClass", .desc = "(Ljava/lang/String;)Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_getGenericSignature0", .desc = "()Ljava/lang/String;" },
    .{ .method = "Java_java_lang_Class_getRawAnnotations", .desc = "()[B" },
    .{ .method = "Java_java_lang_Class_getRawTypeAnnotations", .desc = "()[B" },
    .{ .method = "Java_java_lang_Class_getConstantPool", .desc = "()Ljdk/internal/reflect/ConstantPool;" },
    .{ .method = "Java_java_lang_Class_getDeclaredFields0", .desc = "(Z)[Ljava/lang/reflect/Field;" },
    .{ .method = "Java_java_lang_Class_getDeclaredMethods0", .desc = "(Z)[Ljava/lang/reflect/Method;" },
    .{ .method = "Java_java_lang_Class_getDeclaredConstructors0", .desc = "(Z)[Ljava/lang/reflect/Constructor;" },
    .{ .method = "Java_java_lang_Class_getDeclaredClasses0", .desc = "()[Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_getRecordComponents0", .desc = "()[Ljava/lang/reflect/RecordComponent;" },
    .{ .method = "Java_java_lang_Class_isRecord0", .desc = "()Z" },
    .{ .method = "Java_java_lang_Class_desiredAssertionStatus0", .desc = "(Ljava/lang/Class;)Z" },
    .{ .method = "Java_java_lang_Class_getNestHost0", .desc = "()Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_getNestMembers0", .desc = "()[Ljava/lang/Class;" },
    .{ .method = "Java_java_lang_Class_isHidden", .desc = "()Z" },
    .{ .method = "Java_java_lang_Class_getPermittedSubclasses0", .desc = "()[Ljava/lang/Class;" },
};
