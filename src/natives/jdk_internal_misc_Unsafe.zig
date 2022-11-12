const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_jdk_internal_misc_Unsafe_registerNatives() void {}

pub export fn Java_jdk_internal_misc_Unsafe_arrayBaseOffset0(raw_env: jni.JniEnvPtr, _: sys.jclass, cls: sys.jclass) sys.jint {
    const cls_obj = (jni.convert(cls).toStrong()) orelse return 0;
    const cls_data = cls_obj.get();

    if (!cls_data.isArray()) {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.ClassNotFound)));
        return 0;
    }

    const unsafe = cls_data.unsafeGetArray(.just_offset);
    std.log.debug("arrayBaseOffset0({s}) = {d}", .{ cls_data.name, unsafe.offset });
    return jni.convert(@as(i32, unsafe.offset));
}

pub export fn Java_jdk_internal_misc_Unsafe_arrayIndexScale0(raw_env: jni.JniEnvPtr, _: sys.jclass, cls: sys.jclass) sys.jint {
    const cls_obj = (jni.convert(cls).toStrong()) orelse return 0;
    const cls_data = cls_obj.get();

    if (!cls_data.isArray()) {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.ClassNotFound)));
        return 0;
    }

    const unsafe = cls_data.unsafeGetArray(.just_stride);
    std.log.debug("arrayIndexScale0({s}) = {d}", .{ cls_data.name, unsafe.stride });
    return jni.convert(@as(i32, unsafe.stride));
}

pub export fn Java_jdk_internal_misc_Unsafe_objectFieldOffset1(raw_env: jni.JniEnvPtr, _: sys.jclass, jclass: sys.jclass, jfield_name: sys.jstring) sys.jlong {
    const field_name = jni.convert(jfield_name).toStrongUnchecked(); // null checked by Java caller
    const class = jni.convert(jclass).toStrongUnchecked(); // null checked by Java caller

    // get field name as string
    const thread = jvm.state.thread_state();
    const field_name_utf8 = field_name.get().getStringValueUtf8(thread.global.allocator.inner) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return 0;
    } orelse unreachable; // definitely a string
    defer thread.global.allocator.inner.free(field_name_utf8);

    const unsafe = class.get().unsafeGetInstanceFieldByName(field_name_utf8, .just_offset) orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.Internal)));
        return 0;
    };
    std.log.debug("objectFieldOffset1({s}, {s}) = {d}", .{ class.get().name, field_name_utf8, unsafe.offset });

    return jni.convert(@as(i64, unsafe.offset));
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

const ObjPtr = jvm.VmObjectRef.NullablePtr;
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

fn resolvePtr(comptime T: type, jobj: sys.jobject, offset: sys.jlong) *T {
    const base = if (jni.convert(jobj).toStrong()) |obj| @ptrToInt(obj.get()) else 0; // could be null
    const byte_offset = @intCast(usize, jni.convert(offset)); // never negative
    const byte_ptr = @intToPtr([*]u8, base + byte_offset);
    std.log.debug("resolving unsafe ptr to {s}: base={?}, offset={d}, result={x}", .{ @typeName(T), jni.convert(jobj), byte_offset, @ptrToInt(byte_ptr) });
    return @ptrCast(*T, @alignCast(@alignOf(T), byte_ptr)); // should be well aligned
}

fn compareAndExchange(comptime T: type, jobj: sys.jobject, offset: sys.jlong, expected: Sys(T), x: Sys(T)) ?T {
    const ptr = resolvePtr(T, jobj, offset);

    // hotspot defaults to "conservative" ordering, i.e. 2 way fence
    @fence(.SeqCst);
    const ret = if (T == jvm.VmObjectRef.Nullable)
        jvm.VmObjectRef.Nullable.atomicCompareAndExchange(ptr, jni.convert(expected), jni.convert(x), .Monotonic)
    else
        @cmpxchgStrong(T, ptr, jni.convert(expected), jni.convert(x), .Monotonic, .Monotonic);
    @fence(.SeqCst);

    return ret;
}

fn get(comptime T: type, comptime atomic: enum { volatile_, normal }, jobj: sys.jobject, offset: sys.jlong) Sys(T) {
    const ptr = resolvePtr(T, jobj, offset);

    const loaded = switch (atomic) {
        .volatile_ => if (T == jvm.VmObjectRef.Nullable) jvm.VmObjectRef.Nullable.atomicLoad(ptr, .SeqCst) else @atomicLoad(T, ptr, .SeqCst),
        .normal => ptr.*,
    };
    return sys_convert(loaded);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndSetInt(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jint, x: sys.jint) sys.jboolean {
    return jni.convert(compareAndExchange(i32, jobj, offset, expected, x) == null);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndSetLong(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jlong, x: sys.jlong) sys.jboolean {
    return jni.convert(compareAndExchange(i64, jobj, offset, expected, x) == null);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndSetReference(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jobject, x: sys.jobject) sys.jboolean {
    return jni.convert(compareAndExchange(jvm.VmObjectRef.Nullable, jobj, offset, expected, x) == null);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndExchangeInt(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jint, x: sys.jint) sys.jint {
    return jni.convert(compareAndExchange(i32, jobj, offset, expected, x) orelse expected);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndExchangeLong(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jlong, x: sys.jlong) sys.jlong {
    return jni.convert(compareAndExchange(i64, jobj, offset, expected, x) orelse expected);
}

pub export fn Java_jdk_internal_misc_Unsafe_compareAndExchangeReference(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong, expected: sys.jobject, x: sys.jobject) sys.jobject {
    return if (compareAndExchange(jvm.VmObjectRef.Nullable, jobj, offset, expected, x)) |p| jni.convert(p) else expected;
}

pub export fn Java_jdk_internal_misc_Unsafe_getReferenceVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jobject {
    return get(jvm.object.VmObjectRef.Nullable, .volatile_, jobj, offset);
}

pub export fn Java_jdk_internal_misc_Unsafe_getIntVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jint {
    return get(i32, .volatile_, jobj, offset);
}
pub export fn Java_jdk_internal_misc_Unsafe_getBooleanVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jboolean {
    return get(bool, .volatile_, jobj, offset);
}
// pub export fn Java_jdk_internal_misc_Unsafe_getByteVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jbyte {
//     return get(i8, .volatile_, jobj, offset);
// }
// pub export fn Java_jdk_internal_misc_Unsafe_getShortVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jshort {
//     return get(i16, .volatile_, jobj, offset);
// }
// pub export fn Java_jdk_internal_misc_Unsafe_getCharVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jchar {
//     return get(u16, .volatile_, jobj, offset);
// }
// pub export fn Java_jdk_internal_misc_Unsafe_getLongVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jlong {
//     return get(i64, .volatile_, jobj, offset);
// }
// pub export fn Java_jdk_internal_misc_Unsafe_getDoubleVolatile(_: jni.JniEnvPtr, _: sys.jclass, jobj: sys.jobject, offset: sys.jlong) sys.jdouble {
//     return get(f64, .volatile_, jobj, offset);
// }
pub export fn Java_jdk_internal_misc_Unsafe_ensureClassInitialized0(raw_env: jni.JniEnvPtr, _: sys.jclass, jcls: sys.jclass) void {
    const cls = jni.convert(jcls).toStrongUnchecked();
    jvm.object.VmClass.ensureInitialised(cls) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
    };
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
