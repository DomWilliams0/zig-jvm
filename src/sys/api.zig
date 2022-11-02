const std = @import("std");
const sys = @import("jni.zig");
const jni = @import("root.zig");

pub const JniEnvPtr = [*c][*c]const sys.struct_JNINativeInterface_;

/// A struct just like the original JNINativeInterface_, except function pointers are not optional
pub const JniEnv = blk: {
    const field_count = @typeInfo(sys.struct_JNINativeInterface_).Struct.fields.len;
    var fields: [field_count]std.builtin.Type.StructField = .{undefined} ** field_count;

    inline for (@typeInfo(sys.struct_JNINativeInterface_).Struct.fields) |f, i| {
        var new_field = f;
        comptime var non_optional = @typeInfo(f.field_type).Optional.child;

        switch (@typeInfo(non_optional)) {
            .Pointer => |p| {
                if (p.child != anyopaque)
                    new_field.field_type = non_optional;
            },
            else => {},
        }
        fields[i] = new_field;
    }

    break :blk @Type(.{ .Struct = .{
        .layout = .Extern,
        .is_tuple = false,
        .fields = &fields,
        .decls = &.{},
    } });
};

pub fn makeEnv() JniEnv {
    var result: JniEnv = undefined;
    inline for (@typeInfo(JniEnv).Struct.fields) |f| {
        @field(result, f.name) =
            // leave reserved fields as null. std.mem.startsWith doesn't work for some reason here
            if (f.name.len >= 8 and f.name[0] == 'r' and f.name[1] == 'e' and f.name[2] == 's' and f.name[3] == 'e' and
            f.name[4] == 'r' and f.name[5] == 'v' and f.name[6] == 'e' and f.name[7] == 'd')
            null
        else if (@hasDecl(impl, f.name))
            @field(impl, f.name)
        else blk: {
            const S = struct {
                fn unimplemented(comptime name: []const u8, comptime T: type) T {
                    const inner = struct {
                        fn func() callconv(.C) noreturn {
                            @panic("unimplemented JNI function: " ++ name);
                        }
                    };

                    return @ptrCast(T, &inner.func);
                }
            };

            break :blk S.unimplemented(f.name, f.field_type);
        };
    }
    return result;
}

const impl = struct {
    const state = @import("../state.zig");
    const object = @import("../object.zig");
    pub fn ExceptionCheck(raw_env: JniEnvPtr) callconv(.C) sys.jboolean {
        _ = raw_env;
        // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
        const thread = state.thread_state();
        return if (thread.interpreter.exception.isNull()) sys.JNI_FALSE else sys.JNI_TRUE;
    }

    pub fn Throw(raw_env: JniEnvPtr, exc: sys.jthrowable) callconv(.C) sys.jint {
        _ = raw_env;
        if (jni.convert(exc).toStrong()) |exception| {
            // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
            const thread = state.thread_state();
            thread.interpreter.setException(exception);
            return 0;
        }
        return -1;
    }

    pub fn FindClass(raw_env: JniEnvPtr, cls_name: [*c]const u8) callconv(.C) sys.jclass {
        _ = raw_env;
        // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
        const thread = state.thread_state();
        const loader = if (thread.interpreter.top_frame) |f| f.class.get().loader else @panic("TODO use getSystemClassLoader instead");
        const loaded = thread.global.classloader.loadClass(std.mem.span(cls_name), loader) catch |e| {
            thread.interpreter.setException(state.errorToException(e));
            return null;
        };
        return jni.convert(loaded.clone());
    }

    pub fn NewObjectArray(raw_env: JniEnvPtr, size: sys.jsize, elem: sys.jclass, initial_elem: sys.jobject) callconv(.C) sys.jobjectArray {
        _ = raw_env;

        const elem_cls = jni.convert(elem).toStrongUnchecked();

        // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
        const thread = state.thread_state();

        const array_cls = thread.global.classloader.loadClassAsArrayElement(elem_cls.get().name, elem_cls.get().loader) catch |e| {
            thread.interpreter.setException(state.errorToException(e));
            return null;
        };

        const len = @intCast(usize, size); // expected to be valid
        const array = object.VmClass.instantiateArray(array_cls, len) catch |e| {
            thread.interpreter.setException(state.errorToException(e));
            return null;
        };

        if (!jni.convert(initial_elem).isNull()) @panic("TODO array initial elem");

        return jni.convertObject(sys.jobjectArray, array.intoNullable());
    }

    pub fn GetStringUTFChars(raw_env: JniEnvPtr, string: sys.jstring, is_copy: [*c]sys.jboolean) callconv(.C) [*c]const u8 {
        _ = raw_env;
        const name_obj = jni.convert(string).toStrongUnchecked();

        // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
        const thread = state.thread_state();

        // always copy to null terminate and encode to utf8
        const string_utf8 = name_obj.get().getStringValueUtf8(thread.global.allocator.inner) catch |e| {
            thread.interpreter.setException(state.errorToException(e));
            return null;
        } orelse @panic("not a string");

        if (is_copy) |ptr| ptr.* = sys.JNI_TRUE;
        return string_utf8.ptr;
    }

    pub fn ReleaseStringUTFChars(raw_env: JniEnvPtr, string: sys.jstring, utf: [*c]const u8) callconv(.C) void {
        _ = string;
        _ = raw_env;
        const thread = state.thread_state();
        // is always a copy
        thread.global.allocator.inner.free(std.mem.span(utf));
    }
};

test "env" {
    var env = makeEnv();
    var a: [*c]JniEnv = &env;
    var b: [*c][*c]const JniEnv = &a;
    var c: [*c][*c]const jni.struct_JNINativeInterface_ = @ptrCast([*c][*c]const jni.struct_JNINativeInterface_, b);
    _ = env.ExceptionCheck(c);
}
