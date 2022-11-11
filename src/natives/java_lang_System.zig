const std = @import("std");
const jvm = @import("jvm");
const jni = jvm.jni;
const sys = jni.sys;
const JniEnvPtr = jvm.jni.JniEnvPtr;

pub export fn Java_java_lang_System_registerNatives() void {}

fn arraycopy(src: sys.jobjectArray, src_pos: sys.jint, dst: sys.jobjectArray, dst_pos: sys.jint, length: sys.jint) jvm.state.Error!void {
    var src_end: i32 = undefined;
    var dst_end: i32 = undefined;
    if (src_pos < 0 or dst_pos < 0 or length < 0 or @addWithOverflow(i32, src_pos, length, &src_end) or @addWithOverflow(i32, dst_pos, length, &dst_end))
        return error.IndexOutOfBounds;

    var src_obj = jni.convert(src).toStrong() orelse return error.NullPointer;
    var dst_obj = jni.convert(dst).toStrong() orelse return error.NullPointer;

    var src_cls = src_obj.get().class.get();
    var dst_cls = dst_obj.get().class.get();
    if (!src_cls.isArray() or !dst_cls.isArray()) return error.ArrayStore;

    const src_elem_cls = src_cls.u.array.elem_cls;
    const dst_elem_cls = dst_cls.u.array.elem_cls;

    const src_is_prim = src_elem_cls.get().isPrimitive();
    const valid = if (src_is_prim != dst_elem_cls.get().isPrimitive())
        false // mismatch
    else if (src_is_prim)
        src_elem_cls.get().u.primitive == dst_elem_cls.get().u.primitive
    else
        jvm.object.VmClass.isInstanceOf(src_elem_cls, dst_elem_cls);

    if (!valid) return error.ArrayStore;

    var src_array = src_obj.get().getArrayHeader();
    var dst_array = dst_obj.get().getArrayHeader();

    const elem_sz: usize = src_array.elem_sz;
    if (src_elem_cls.get().isPrimitive()) {
        // copy byte slice
        std.debug.assert(elem_sz == dst_array.elem_sz);

        const src_slice = src_array.getElemsRaw()[@intCast(usize, src_pos) * elem_sz .. @intCast(usize, src_end) * elem_sz];
        const dst_slice = dst_array.getElemsRaw()[@intCast(usize, dst_pos) * elem_sz .. @intCast(usize, dst_end) * elem_sz];
        std.mem.copy(u8, dst_slice, src_slice);
    } else {
        const src_slice = src_array.getElems(jvm.VmObjectRef.Nullable)[@intCast(usize, src_pos)..@intCast(usize, src_end)];
        const dst_slice = dst_array.getElems(jvm.VmObjectRef.Nullable)[@intCast(usize, dst_pos)..@intCast(usize, dst_end)];
        for (src_slice) |obj, i| {
            const obj_copy = if (obj.toStrong()) |o| o.clone().intoNullable() else obj;
            dst_slice[i] = obj_copy;
        }
    }
}
pub export fn Java_java_lang_System_arraycopy(raw_env: JniEnvPtr, system_cls: sys.jclass, src: sys.jobjectArray, src_pos: sys.jint, dst: sys.jobjectArray, dst_pos: sys.jint, length: sys.jint) void {
    _ = system_cls;

    arraycopy(src, src_pos, dst, dst_pos, length) catch |e| {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(e)));
        return;
    };
}

pub export fn Java_java_lang_System_setIn0(raw_env: JniEnvPtr, system_cls: sys.jclass, jfile: sys.jobject) void {
    const cls = jni.convert(system_cls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return;
    };

    jvm.call.setStaticField(cls, "in", "Ljava/io/InputStream;", jni.convert(jfile)) catch {};
}

pub export fn Java_java_lang_System_setOut0(raw_env: JniEnvPtr, system_cls: sys.jclass, jfile: sys.jobject) void {
    const cls = jni.convert(system_cls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return;
    };

    jvm.call.setStaticField(cls, "out", "Ljava/io/PrintStream;", jni.convert(jfile)) catch {};
}

pub export fn Java_java_lang_System_setErr0(raw_env: JniEnvPtr, system_cls: sys.jclass, jfile: sys.jobject) void {
    const cls = jni.convert(system_cls).toStrong() orelse {
        _ = jni.convert(raw_env).Throw(raw_env, jni.convert(jvm.state.errorToException(error.NullPointer)));
        return;
    };

    jvm.call.setStaticField(cls, "err", "Ljava/io/PrintStream;", jni.convert(jfile)) catch {};
}

pub const methods = [_]@import("root.zig").JniMethod{
    .{ .method = "Java_java_lang_System_registerNatives", .desc = "()V" },
    .{ .method = "Java_java_lang_System_setIn0", .desc = "(Ljava/io/InputStream;)V" },
    .{ .method = "Java_java_lang_System_setOut0", .desc = "(Ljava/io/PrintStream;)V" },
    .{ .method = "Java_java_lang_System_setErr0", .desc = "(Ljava/io/PrintStream;)V" },
    .{ .method = "Java_java_lang_System_currentTimeMillis", .desc = "()J" },
    .{ .method = "Java_java_lang_System_nanoTime", .desc = "()J" },
    .{ .method = "Java_java_lang_System_arraycopy", .desc = "(Ljava/lang/Object;ILjava/lang/Object;II)V" },
    .{ .method = "Java_java_lang_System_identityHashCode", .desc = "(Ljava/lang/Object;)I" },
    .{ .method = "Java_java_lang_System_mapLibraryName", .desc = "(Ljava/lang/String;)Ljava/lang/String;" },
};
