pub const api = @import("api.zig");
pub const sys = @import("jni.zig");

pub const JniEnv = api.JniEnv;
pub const JniEnvPtr = api.JniEnvPtr;

const object = @import("../object.zig");
const VmObjectRef = object.VmObjectRef;
const VmClassRef = object.VmClassRef;

pub fn ConversionType(comptime from: type) type {
    return switch (from) {
        JniEnvPtr => *const JniEnv,

        sys.jclass => VmClassRef.Nullable,
        VmClassRef, VmClassRef.Nullable => sys.jclass,

        sys.jobject => VmObjectRef.Nullable,
        VmObjectRef, VmObjectRef.Nullable, VmObjectRef.NullablePtr => sys.jobject,

        sys.jarray, sys.jbooleanArray, sys.jbyteArray, sys.jcharArray, sys.jshortArray, sys.jintArray, sys.jlongArray, sys.jfloatArray, sys.jdoubleArray, sys.jobjectArray => VmObjectRef.Nullable,
        sys.jstring => VmObjectRef.Nullable,

        sys.jlong => i64,
        sys.jint => i32,
        sys.jchar => u16,
        sys.jshort => i16,

        i64 => sys.jlong,
        i32 => sys.jint,
        bool => sys.jboolean,
        u16 => sys.jchar,
        i16 => sys.jshort,
        i8 => sys.jbyte,
        f64 => sys.jdouble,
        f32 => sys.jfloat,
        else => @compileError("TODO convert type: " ++ @typeName(from)),
    };
}

fn vmRefToRaw(comptime T: type, vmref: anytype) T {
    return @ptrCast(vmref.ptr);
}

fn rawToVmRef(comptime T: type, raw: anytype) T.Nullable {
    return T.Nullable{ .ptr = @ptrCast(@alignCast(raw)) };
}

pub fn convert(val: anytype) ConversionType(@TypeOf(val)) {
    return switch (@TypeOf(val)) {
        JniEnvPtr => @ptrCast(val.*),
        sys.jclass => blk: {
            const java_lang_Class_instance = rawToVmRef(VmObjectRef, val).toStrong() orelse break :blk VmClassRef.Nullable.nullRef();
            const cls = java_lang_Class_instance.get().getClassDataUnchecked();
            break :blk cls.clone().intoNullable(); // TODO need to clone?
        },
        VmClassRef => vmRefToRaw(sys.jclass, val.get().getClassInstance().clone()),
        VmClassRef.Nullable => if (val.toStrong()) |c| vmRefToRaw(sys.jclass, c.get().getClassInstance().clone()) else null,

        sys.jarray, sys.jbooleanArray, sys.jbyteArray, sys.jcharArray, sys.jshortArray, sys.jintArray, sys.jlongArray, sys.jfloatArray, sys.jdoubleArray, sys.jobjectArray => rawToVmRef(VmObjectRef, val),
        sys.jstring => rawToVmRef(VmObjectRef, val),

        sys.jobject => rawToVmRef(VmObjectRef, val),
        VmObjectRef => vmRefToRaw(sys.jobject, val),
        VmObjectRef.Nullable => vmRefToRaw(sys.jobject, val),
        VmObjectRef.NullablePtr => vmRefToRaw(sys.jobject, VmObjectRef.Nullable.fromPtr(val)),

        sys.jlong, sys.jint, sys.jbyte, sys.jboolean, sys.jchar, sys.jshort, sys.jfloat, sys.jdouble => val,

        bool => if (val) sys.JNI_TRUE else sys.JNI_FALSE,
        i32, i64, i16, u16 => val,

        else => @compileError("TODO convert from " ++ @typeName(@TypeOf(val))),
    };
}

pub fn convertObject(comptime T: type, val: anytype) T {
    switch (T) {
        sys.jclass, sys.jthrowable, sys.jstring, sys.jarray, sys.jbooleanArray, sys.jbyteArray, sys.jcharArray, sys.jshortArray, sys.jintArray, sys.jlongArray, sys.jfloatArray, sys.jdoubleArray, sys.jobjectArray, sys.jweak => {},
        else => @compileError("cannot convert " ++ @typeName(T) ++ " to jobject"),
    }

    const nullable = switch (@TypeOf(val)) {
        VmObjectRef => val.intoNullable(),
        VmObjectRef.Nullable => val,
        else => @compileError("not an object " ++ @typeName(@TypeOf(val))),
    };

    return vmRefToRaw(T, nullable);
}
