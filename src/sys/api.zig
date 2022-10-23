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
        const non_optional = @typeInfo(f.field_type).Optional.child;

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

pub fn convertEnv(raw_env: JniEnvPtr) *const JniEnv {
    return @ptrCast(*const JniEnv, raw_env.*);
}
const impl = struct {
    const state = @import("../state.zig");
    pub export fn ExceptionCheck(raw_env: JniEnvPtr) sys.jboolean {
        _ = raw_env;
        // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
        const thread = state.thread_state();
        return if (thread.interpreter.exception.isNull()) sys.JNI_FALSE else sys.JNI_TRUE;
    }

    pub export fn Throw(raw_env: JniEnvPtr, exc: sys.jobject) sys.jint {
        _ = raw_env;
        if (jni.convert(sys.jobject).from(exc).toStrong()) |exception| {
            // TODO store the *ThreadEnv at the end of JniEnv instead of looking up from threadlocal every time
            const thread = state.thread_state();
            thread.interpreter.setException(exception);
            return 0;
        }
        return -1;
    }
};

// test "env" {
//     var env = makeEnv();
//     var a: [*c]JniEnv = &env;
//     var b: [*c][*c]const JniEnv = &a;
//     var c: [*c][*c]const jni.struct_JNINativeInterface_ = @ptrCast([*c][*c]const jni.struct_JNINativeInterface_, b);
//     _ = env.ExceptionCheck(c);
// }
