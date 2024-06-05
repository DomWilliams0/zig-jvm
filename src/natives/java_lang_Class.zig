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
    const cls_name_c = env.GetStringUTFChars(raw_env, name, &is_copy) orelse {
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

fn getDeclaredFields(raw_env: JniEnvPtr, cls: jvm.VmClassRef, public_only: bool) jvm.state.Error!sys.jobjectArray {
    const t = jvm.state.thread_state();
    const env = jni.convert(raw_env);

    // TODO cache these
    const field_cls = try t.global.classloader.loadClass("java/lang/reflect/Field", .bootstrap);
    const array_cls = try t.global.classloader.loadClass("[Ljava/lang/reflect/Field;", .bootstrap);

    if (!cls.get().isObject()) {
        // empty array
        return jni.convertObject(sys.jobjectArray, try jvm.object.VmClass.instantiateArray(array_cls, 0));
    }

    const all_fields = cls.get().u.obj.fields;
    const filtered_fields_len = if (!public_only) all_fields.len else blk: {
        var count: usize = 0;
        for (all_fields) |f| {
            if (f.flags.contains(.public)) count += 1;
        }
        break :blk count;
    };
    const array = try jvm.object.VmClass.instantiateArray(array_cls, filtered_fields_len);
    const jarray = jni.convertObject(sys.jobjectArray, array);

    var idx: i32 = 0;
    for (all_fields, 0..) |f, i| {
        if (!public_only or !f.flags.contains(.public)) continue;

        const name = try t.global.string_pool.getString(f.name);
        const signature = try t.global.string_pool.getString(f.descriptor.str);
        // quicker to use jvm functions here instead of via jni
        // TODO get current class loader instead of bootstrap
        const ty = switch (f.descriptor.getType()) {
            .primitive => |p| t.global.classloader.getLoadedPrimitive(p),
            .reference => |refname| try t.global.classloader.loadClass(refname, .bootstrap),
            .array => |arrname| try t.global.classloader.loadClassAsArrayElement(arrname, .bootstrap),
        };
        const field_instance = try jvm.object.VmClass.instantiateObject(field_cls, .ensure_initialised);
        _ = try jvm.call.runMethod(t, field_cls, "<init>", "(Ljava/lang/Class;Ljava/lang/String;Ljava/lang/Class;IZILjava/lang/String;[B)V", .{ field_instance, cls.get().getClassInstance(), name, ty.get().getClassInstance(), f.flags.bits, false, @as(i32, @intCast(i)), signature, jvm.object.VmObjectRef.Nullable.nullRef() });

        env.SetObjectArrayElement(raw_env, jarray, idx, jni.convert(field_instance));
        idx += 1;
    }

    return jarray;
}

pub export fn Java_java_lang_Class_getDeclaredFields0(raw_env: JniEnvPtr, jclass: sys.jclass, public_only: sys.jboolean) sys.jobjectArray {
    const cls = jni.convert(jclass).toStrongUnchecked();
    return getDeclaredFields(raw_env, cls, public_only != sys.JNI_FALSE) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
}

fn getInterfaces(raw_env: JniEnvPtr, cls: jvm.VmClassRef) jvm.state.Error!sys.jobjectArray {
    const t = jvm.state.thread_state();
    const env = jni.convert(raw_env);

    const array_cls = try t.global.classloader.loadClass("[Ljava/lang/Class;", .bootstrap);

    const ifaces = cls.get().interfaces;
    const array = try jvm.object.VmClass.instantiateArray(array_cls, ifaces.len);
    const jarray = jni.convertObject(sys.jobjectArray, array);

    for (ifaces, 0..) |iface, i| {
        env.SetObjectArrayElement(raw_env, jarray, @intCast(i), jni.convert(iface.cast(jvm.object.VmObject)));
    }

    return jarray;
}

pub export fn Java_java_lang_Class_getInterfaces0(raw_env: JniEnvPtr, jclass: sys.jclass) sys.jobjectArray {
    const cls = jni.convert(jclass).toStrongUnchecked();
    return getInterfaces(raw_env, cls) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
}

fn getDeclaredConstructors(raw_env: JniEnvPtr, cls: jvm.VmClassRef, public_only: bool) jvm.state.Error!sys.jobjectArray {
    const t = jvm.state.thread_state();
    const env = jni.convert(raw_env);

    // TODO cache these
    const cons_cls = try t.global.classloader.loadClass("java/lang/reflect/Constructor", .bootstrap);
    const array_cls = try t.global.classloader.loadClass("[Ljava/lang/reflect/Constructor;", .bootstrap);
    const cls_array_cls = try t.global.classloader.loadClass("[Ljava/lang/Class;", .bootstrap);

    if (!cls.get().isObject()) {
        // empty array
        return jni.convertObject(sys.jobjectArray, try jvm.object.VmClass.instantiateArray(array_cls, 0));
    }

    const all_methods = cls.get().u.obj.methods;
    const filtered_methods_len = blk: {
        var count: usize = 0;
        for (all_methods) |m| {
            if ((!public_only or m.flags.contains(.public)) and std.mem.eql(u8, m.name, "<init>")) count += 1;
        }
        break :blk count;
    };
    const array = try jvm.object.VmClass.instantiateArray(array_cls, filtered_methods_len);
    const jarray = jni.convertObject(sys.jobjectArray, array);

    var idx: i32 = 0;
    for (all_methods, 0..) |m, i| {
        if ((!public_only or m.flags.contains(.public)) and std.mem.eql(u8, m.name, "<init>")) {
            const param_types = blk: {
                var params_array = try jvm.object.VmClass.instantiateArray(cls_array_cls, m.descriptor.param_count);
                const arr = params_array.get().getArrayHeader().getElems(jvm.VmObjectRef.Nullable);
                var params = m.descriptor.iterateParamTypes();
                var p: usize = 0;
                while (params.next()) |param| {
                    const param_cls =
                        switch (param.getType()) {
                        .primitive => |prim| t.global.classloader.getLoadedPrimitive(prim),
                        else => try t.global.classloader.loadClass(param.str, .bootstrap),
                    };

                    arr[p] = param_cls.get().getClassInstance().intoNullable();
                    p += 1;
                }

                break :blk params_array;
            };

            // TODO parse out checked exceptions
            const decl_cls = cls.get().getClassInstance().intoNullable();
            const checked_exceptions = try jvm.object.VmClass.instantiateArray(cls_array_cls, 0);
            const modifiers: i32 = @intCast(m.flags.bits);
            const slot: i32 = @intCast(i);
            const signature = try t.global.string_pool.getString(m.descriptor.str);
            const annotations = jvm.VmObjectRef.Nullable.nullRef(); // TODO
            const param_annotations = jvm.VmObjectRef.Nullable.nullRef(); // TODO

            const instance = try jvm.object.VmClass.instantiateObject(cons_cls, .ensure_initialised);
            _ = try jvm.call.runMethod(t, cons_cls, "<init>", "(Ljava/lang/Class;[Ljava/lang/Class;[Ljava/lang/Class;IILjava/lang/String;[B[B)V", .{ instance.intoNullable(), decl_cls, param_types, checked_exceptions, modifiers, slot, signature, annotations, param_annotations });

            env.SetObjectArrayElement(raw_env, jarray, idx, jni.convert(instance));
            idx += 1;
        }
    }

    return jarray;
}

pub export fn Java_java_lang_Class_getDeclaredConstructors0(raw_env: JniEnvPtr, jclass: sys.jclass, public_only: sys.jboolean) sys.jobjectArray {
    const cls = jni.convert(jclass).toStrongUnchecked();
    return getDeclaredConstructors(raw_env, cls, public_only != sys.JNI_FALSE) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return null;
    };
}

pub export fn Java_java_lang_Class_getSuperclass(raw_env: JniEnvPtr, jclass: sys.jclass) sys.jclass {
    _ = raw_env;
    const cls = jni.convert(jclass).toStrong() orelse return null;
    return jni.convert(cls.get().super_cls);
}

pub export fn Java_java_lang_Class_isAssignableFrom(raw_env: JniEnvPtr, jclass: sys.jclass, other_class: sys.jclass) sys.jboolean {
    const this_cls = jni.convert(jclass).toStrong() orelse return sys.JNI_FALSE;
    const other_cls = jni.convert(other_class).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return sys.JNI_FALSE;
    };

    const eq = if (this_cls.get().isPrimitive())
        this_cls.cmpPtr(other_cls) // must be same class
    else
        jvm.object.VmClass.isSuperClassOrSuperInterface(other_cls, this_cls);

    return if (eq) sys.JNI_TRUE else sys.JNI_FALSE;
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
