pub const api = @import("api.zig");
pub const sys = @import("jni.zig");

pub const JniEnv = api.JniEnv;
pub const JniEnvPtr = api.JniEnvPtr;

const object = @import("../object.zig");
const VmObjectRef = object.VmObjectRef;
const VmClassRef = object.VmClassRef;

fn ConversionType(comptime from: type) type {
    return switch (from) {
        JniEnvPtr => *const JniEnv,

        sys.jclass => VmClassRef.Nullable,
        VmClassRef => sys.jclass,

        sys.jobject => VmObjectRef.Nullable,
        VmObjectRef => sys.jobject,

        sys.jobjectArray => VmObjectRef.Nullable,
        sys.jstring => VmObjectRef.Nullable,

        bool => sys.jboolean,
        i64 => sys.jlong,
        i32 => sys.jint,
        else => @compileError("TODO convert type: " ++ @typeName(from)),
    };
}

fn vmRefToRaw(comptime T: type, vmref: anytype) T {
    return @ptrCast(T, vmref.ptr);
}

fn rawToVmRef(comptime T: type, raw: anytype) T.Nullable {
    return T.Nullable{ .ptr = @ptrCast(T.NullablePtr, @alignCast(@alignOf(T.NullablePtr), raw)) };
}

pub fn convert(val: anytype) ConversionType(@TypeOf(val)) {
    return switch (@TypeOf(val)) {
        JniEnvPtr => @ptrCast(*const JniEnv, val.*),
        sys.jclass => blk: {
            const java_lang_Class_instance = rawToVmRef(VmObjectRef, val).toStrong() orelse break :blk VmClassRef.Nullable.nullRef();
            const cls = java_lang_Class_instance.get().getClassDataUnchecked();
            break :blk cls.clone().intoNullable(); // TODO need to clone?
        },
        VmClassRef => vmRefToRaw(sys.jclass, val.get().getClassInstance().clone()),

        sys.jobjectArray => rawToVmRef(VmObjectRef, val),
        sys.jstring => rawToVmRef(VmObjectRef, val),

        sys.jobject => rawToVmRef(VmObjectRef, val),
        VmObjectRef => vmRefToRaw(sys.jobject, val),

        bool => if (val) sys.JNI_TRUE else sys.JNI_FALSE,
        i64, i32 => val,

        else => @compileError("TODO convert from " ++ @typeName(@TypeOf(val))),
    };
}

pub fn convertObject(comptime T: type, val: VmObjectRef.Nullable) T {
    switch (T) {
        sys.jclass, sys.jthrowable, sys.jstring, sys.jarray, sys.jbooleanArray, sys.jbyteArray, sys.jcharArray, sys.jshortArray, sys.jintArray, sys.jlongArray, sys.jfloatArray, sys.jdoubleArray, sys.jobjectArray, sys.jweak => {},
        else => @compileError("cannot convert " ++ @typeName(T) ++ " to jobject"),
    }

    return vmRefToRaw(T, val);
}
