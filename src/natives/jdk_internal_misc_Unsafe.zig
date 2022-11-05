const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_jdk_internal_misc_Unsafe_registerNatives() void {}

pub export fn Java_jdk_internal_misc_Unsafe_arrayBaseOffset0(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, cls: sys.jclass) sys.jint {
    _ = unsafe_cls;
    const cls_obj = (jni.convert(cls).toStrong()) orelse return 0;
    const cls_data = cls_obj.get();

    if (!cls_data.isArray()) {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.ClassNotFound)));
        return 0;
    }

    const offset = @intCast(sys.jint, cls_data.getArrayBaseOffset());
    std.log.debug("arrayBaseOffset0({s}) = {d}", .{ cls_data.name, offset });
    return offset;
}

pub export fn Java_jdk_internal_misc_Unsafe_arrayIndexScale0(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, cls: sys.jclass) sys.jint {
    _ = unsafe_cls;
    const cls_obj = (jni.convert(cls).toStrong()) orelse return 0;
    const cls_data = cls_obj.get();

    if (!cls_data.isArray()) {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.ClassNotFound)));
        return 0;
    }

    const ret = @intCast(sys.jint, cls_data.getArrayStride());
    std.log.debug("arrayIndexScale0({s}) = {d}", .{ cls_data.name, ret });
    return ret;
}

pub export fn Java_jdk_internal_misc_Unsafe_objectFieldOffset0(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jfield: sys.jobject) sys.jlong {
    _ = unsafe_cls;
    _ = raw_env;

    const field = jni.convert(jfield).toStrongUnchecked(); // null checked by Java caller

    const s = jvm.object.VmObject.toString(field);
    _ = s;

    unreachable;
}

pub export fn Java_jdk_internal_misc_Unsafe_objectFieldOffset1(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jclass: sys.jclass, jfield_name: sys.jstring) sys.jlong {
    _ = unsafe_cls;

    const field_name = jni.convert(jfield_name).toStrongUnchecked(); // null checked by Java caller
    const class = jni.convert(jclass).toStrongUnchecked(); // null checked by Java caller

    // get field name as string
    const thread = jvm.state.thread_state();
    const field_name_utf8 = field_name.get().getStringValueUtf8(thread.global.allocator.inner) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return 0;
    } orelse unreachable; // definitely a string
    defer thread.global.allocator.inner.free(field_name_utf8);

    const field = class.get().findFieldByName(field_name_utf8) orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.Internal)));
        return 0;
    };

    const val: i64 = if (field.flags.contains(.static))
        @intCast(i64, @ptrToInt(&field.u.value)) // ptr to static value
    else
        @intCast(i64, field.u.layout_offset); // offset into object

    return jni.convert(val);
}

pub export fn Java_jdk_internal_misc_Unsafe_fullFence() void {
    @fence(.Acquire);
}

fn Sys(comptime from: type) type {
    return switch (from) {
        bool => sys.jboolean,
        i64 => sys.jlong,
        i32 => sys.jint,
        i8 => sys.jbyte,
        u16 => sys.jchar,
        i16 => sys.jshort,
        f32 => sys.jfloat,
        f64 => sys.jdouble,
        jvm.VmObjectRef.Nullable => sys.jobject,
        else => @compileError("no mapping for " ++ @typeName(from)),
    };
}

const ObjPtr = jvm.VmObjectRef.Nullable.AsPointer;
fn SysConvert(comptime from: type) type {
    return switch (from) {
        sys.jobject => ObjPtr,
        else => jni.ConversionType(from),
    };
}

fn sys_convert(val: anytype) SysConvert(@TypeOf(val)) {
    return switch (@TypeOf(val)) {
        sys.jobject => jni.convert(val).intoPtr(),
        else => jni.convert(val),
    };
}

fn compareAndSet(comptime T: type, jobj: sys.jobject, offset: sys.jlong, expected: Sys(T), x: Sys(T)) sys.jboolean {
    const obj = jni.convert(jobj).toStrongUnchecked(); // no null
    const byte_offset = @intCast(usize, jni.convert(offset)); // assume offset comes from other Unsafe native methods, so won't be negative or invalid

    const cmp_ty = if (T == jvm.VmObjectRef.Nullable) ObjPtr else T;
    const ptr = obj.get().getFieldFromOffset(cmp_ty, byte_offset);

    // hotspot uses "conservative" ordering, i.e. 2 way fence
    @fence(.SeqCst);
    const ret = @cmpxchgStrong(cmp_ty, ptr, sys_convert(expected), sys_convert(x), .Monotonic, .Monotonic) == null;
    @fence(.SeqCst);

    return jni.convert(ret);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndSetInt(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jint, x: sys.jint) sys.jboolean {
    _ = unsafe_cls;
    _ = raw_env;
    return compareAndSet(i32, jobj, offset, expected, x);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndSetLong(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jlong, x: sys.jlong) sys.jboolean {
    _ = unsafe_cls;
    _ = raw_env;
    return compareAndSet(i64, jobj, offset, expected, x);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndSetReference(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jobject, x: sys.jobject) sys.jboolean {
    _ = unsafe_cls;
    _ = raw_env;
    // TODO is this adding an extra layer of indirection?
    return compareAndSet(jvm.VmObjectRef.Nullable, jobj, offset, expected, x);
}

fn get(comptime T: type, comptime atomic: enum { volatile_, normal }, jobj: sys.jobject, offset: sys.jlong) Sys(T) {
    const byte_offset = @intCast(usize, jni.convert(offset)); // assume offset comes from other Unsafe native methods, so won't be negative or invalid
    const load_ty = if (T == jvm.VmObjectRef.Nullable) ObjPtr else T;

    if (jni.convert(jobj).toStrong()) |obj| {
        // instance field
        const ptr = obj.get().getFieldFromOffset(load_ty, byte_offset);
        const loaded = switch (atomic) {
            .volatile_ => @atomicLoad(load_ty, ptr, .SeqCst),
            .normal => ptr.*,
        };
        return sys_convert(loaded);
    } else @panic("TODO static field");
}

pub export fn Java_jdk_internal_misc_Unsafe_getReferenceVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jobject {
    _ = unsafe_cls;
    _ = raw_env;
    return get(jvm.object.VmObjectRef.Nullable, .volatile_, jobj, offset);
}

pub export fn Java_jdk_internal_misc_Unsafe_getIntVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jint {
    _ = unsafe_cls;
    _ = raw_env;
    return get(i32, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getBooleanVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jboolean {
    _ = unsafe_cls;
    _ = raw_env;
    return get(bool, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getByteVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jbyte {
    _ = unsafe_cls;
    _ = raw_env;
    return get(i8, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getShortVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jshort {
    _ = unsafe_cls;
    _ = raw_env;
    return get(i16, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getCharVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jchar {
    _ = unsafe_cls;
    _ = raw_env;
    return get(u16, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getLongVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jlong {
    _ = unsafe_cls;
    _ = raw_env;
    return get(i64, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getDoubleVolatile(raw_env: jni.JniEnvPtr, unsafe_cls: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jdouble {
    _ = unsafe_cls;
    _ = raw_env;
    return get(f64, .volatile_, jobj, offset);
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_jdk_internal_misc_Unsafe_registerNatives", .desc = "()V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getInt", .desc = "(Ljava/lang/Object;J)I" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putInt", .desc = "(Ljava/lang/Object;JI)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getReference", .desc = "(Ljava/lang/Object;J)Ljava/lang/Object;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putReference", .desc = "(Ljava/lang/Object;JLjava/lang/Object;)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getBoolean", .desc = "(Ljava/lang/Object;J)Z" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putBoolean", .desc = "(Ljava/lang/Object;JZ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getByte", .desc = "(Ljava/lang/Object;J)B" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putByte", .desc = "(Ljava/lang/Object;JB)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getShort", .desc = "(Ljava/lang/Object;J)S" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putShort", .desc = "(Ljava/lang/Object;JS)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getChar", .desc = "(Ljava/lang/Object;J)C" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putChar", .desc = "(Ljava/lang/Object;JC)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getLong", .desc = "(Ljava/lang/Object;J)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putLong", .desc = "(Ljava/lang/Object;JJ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getFloat", .desc = "(Ljava/lang/Object;J)F" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putFloat", .desc = "(Ljava/lang/Object;JF)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getDouble", .desc = "(Ljava/lang/Object;J)D" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putDouble", .desc = "(Ljava/lang/Object;JD)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getUncompressedObject", .desc = "(J)Ljava/lang/Object;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_writeback0", .desc = "(J)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_writebackPreSync0", .desc = "()V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_writebackPostSync0", .desc = "()V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_defineClass0", .desc = "(Ljava/lang/String;[BIILjava/lang/ClassLoader;Ljava/security/ProtectionDomain;)Ljava/lang/Class;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_allocateInstance", .desc = "(Ljava/lang/Class;)Ljava/lang/Object;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_throwException", .desc = "(Ljava/lang/Throwable;)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_compareAndSetReference", .desc = "(Ljava/lang/Object;JLjava/lang/Object;Ljava/lang/Object;)Z" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_compareAndExchangeReference", .desc = "(Ljava/lang/Object;JLjava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_compareAndSetInt", .desc = "(Ljava/lang/Object;JII)Z" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_compareAndExchangeInt", .desc = "(Ljava/lang/Object;JII)I" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_compareAndSetLong", .desc = "(Ljava/lang/Object;JJJ)Z" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_compareAndExchangeLong", .desc = "(Ljava/lang/Object;JJJ)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getReferenceVolatile", .desc = "(Ljava/lang/Object;J)Ljava/lang/Object;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putReferenceVolatile", .desc = "(Ljava/lang/Object;JLjava/lang/Object;)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getIntVolatile", .desc = "(Ljava/lang/Object;J)I" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putIntVolatile", .desc = "(Ljava/lang/Object;JI)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getBooleanVolatile", .desc = "(Ljava/lang/Object;J)Z" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putBooleanVolatile", .desc = "(Ljava/lang/Object;JZ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getByteVolatile", .desc = "(Ljava/lang/Object;J)B" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putByteVolatile", .desc = "(Ljava/lang/Object;JB)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getShortVolatile", .desc = "(Ljava/lang/Object;J)S" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putShortVolatile", .desc = "(Ljava/lang/Object;JS)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getCharVolatile", .desc = "(Ljava/lang/Object;J)C" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putCharVolatile", .desc = "(Ljava/lang/Object;JC)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getLongVolatile", .desc = "(Ljava/lang/Object;J)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putLongVolatile", .desc = "(Ljava/lang/Object;JJ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getFloatVolatile", .desc = "(Ljava/lang/Object;J)F" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putFloatVolatile", .desc = "(Ljava/lang/Object;JF)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getDoubleVolatile", .desc = "(Ljava/lang/Object;J)D" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_putDoubleVolatile", .desc = "(Ljava/lang/Object;JD)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_unpark", .desc = "(Ljava/lang/Object;)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_park", .desc = "(ZJ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_fullFence", .desc = "()V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_allocateMemory0", .desc = "(J)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_reallocateMemory0", .desc = "(JJ)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_freeMemory0", .desc = "(J)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_setMemory0", .desc = "(Ljava/lang/Object;JJB)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_copyMemory0", .desc = "(Ljava/lang/Object;JLjava/lang/Object;JJ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_copySwapMemory0", .desc = "(Ljava/lang/Object;JLjava/lang/Object;JJJ)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_objectFieldOffset0", .desc = "(Ljava/lang/reflect/Field;)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_objectFieldOffset1", .desc = "(Ljava/lang/Class;Ljava/lang/String;)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_staticFieldOffset0", .desc = "(Ljava/lang/reflect/Field;)J" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_staticFieldBase0", .desc = "(Ljava/lang/reflect/Field;)Ljava/lang/Object;" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_shouldBeInitialized0", .desc = "(Ljava/lang/Class;)Z" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_ensureClassInitialized0", .desc = "(Ljava/lang/Class;)V" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_arrayBaseOffset0", .desc = "(Ljava/lang/Class;)I" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_arrayIndexScale0", .desc = "(Ljava/lang/Class;)I" },
    .{ .method = "Java_jdk_internal_misc_Unsafe_getLoadAverage0", .desc = "([DI)I" },
};
