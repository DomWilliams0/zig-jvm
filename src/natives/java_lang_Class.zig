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
pub export fn Java_java_lang_Class_getPrimitiveClass(raw_env: JniEnvPtr, cls: sys.jclass, name: sys.jstring) sys.jclass {
    _ = cls;
    const env = jni.convert(raw_env);
    if (name == null) {
        // TODO wew, make this more ergonomic
        const exc = jvm.state.errorToException(error.NullPointer);
        _ = env.Throw(raw_env, jni.convert(exc));
        return null;
    }

    const string = env.GetStringUTFChars(raw_env, name, null);
    defer env.ReleaseStringUTFChars(raw_env, name, string);

    std.log.debug("GetPrimitiveClass({s})", .{string});
    const ty = jvm.types.DataType.fromName(std.mem.span(string), true) orelse {
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(error.ClassNotFound)));
        return null;
    };
    const prim = ty.asPrimitive() orelse unreachable; // impossible

    const prim_cls = jvm.state.thread_state().global.classloader.getLoadedPrimitive(prim);
    return jni.convert(prim_cls);
}

pub export fn Java_java_lang_Class_isPrimitive(raw_env: JniEnvPtr, jcls: sys.jclass) sys.jboolean {
    const cls = jni.convert(jcls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return sys.JNI_FALSE;
    };

    return jni.convert(cls.get().isPrimitive());
}
pub export fn Java_java_lang_Class_isArray(raw_env: JniEnvPtr, jcls: sys.jclass) sys.jboolean {
    const cls = jni.convert(jcls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return sys.JNI_FALSE;
    };

    return jni.convert(cls.get().isArray());
}
pub export fn Java_java_lang_Class_isInterface(raw_env: JniEnvPtr, jcls: sys.jclass) sys.jboolean {
    const cls = jni.convert(jcls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return sys.JNI_FALSE;
    };

    return jni.convert(cls.get().isInterface());
}

pub export fn Java_java_lang_Class_forName0(raw_env: JniEnvPtr, _: sys.jclass, name: sys.jstring, initialize: sys.jboolean, jloader: sys.jobject, caller: sys.jclass) sys.jclass {
    _ = caller;

    const env = jni.convert(raw_env);
    const t = jvm.state.thread_state();
    var is_copy: sys.jboolean = undefined;
    var cls_name_c = env.GetStringUTFChars(raw_env, name, &is_copy) orelse {
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return null;
    };
    defer env.ReleaseStringUTFChars(raw_env, name, cls_name_c);

    // copy locally to replace . with /
    const cls_name_mangled = t.global.classloader.alloc.dupe(u8, std.mem.span(cls_name_c)) catch |e| {
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
    defer t.global.classloader.alloc.free(cls_name_mangled);
    std.mem.replaceScalar(u8, cls_name_mangled, '.', '/');

    const loader: jvm.classloader.WhichLoader = if (jni.convert(jloader).toStrong()) |l| .{ .user = l } else .bootstrap;

    const cls = t.global.classloader.loadClass(cls_name_mangled, loader) catch |e| {
        _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };

    if (initialize == sys.JNI_TRUE) {
        jvm.object.VmClass.ensureInitialised(cls) catch |e| {
            _ = env.Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
            return null;
        };
    }

    return jni.convert(cls.clone());
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
