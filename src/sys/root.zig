const jvm = @import("jvm");
const jni = @import("jni.zig");
pub const api = @import("api.zig");
pub usingnamespace jni;

const VmObjectRef = jvm.object.VmObjectRef;
pub fn convert(comptime jni_type: type) type {
    switch (jni_type) {
        jni.jobject => return struct {
            pub fn from(obj: jni.jobject) VmObjectRef.Nullable {
                return VmObjectRef.Nullable{ .ptr = @ptrCast(VmObjectRef.NullablePtr, @alignCast(@alignOf(VmObjectRef.NullablePtr), obj)) };
            }

            // TODO allow non nullable too
            pub fn to(obj: VmObjectRef.Nullable) jni.jobject {
                return @ptrCast(jni.jobject, obj.ptr);
            }
        },
        else => @compileError("TODO convert jni type: " ++ @typeName(jni_type)),
    }
}
