comptime {
    validateFunctionSignatures(@import("java_lang_Throwable.zig"));
    validateFunctionSignatures(@import("java_lang_Class.zig"));
    validateFunctionSignatures(@import("java_lang_Object.zig"));
    validateFunctionSignatures(@import("java_lang_System.zig"));
    validateFunctionSignatures(@import("jdk_internal_misc_Unsafe.zig"));
    validateFunctionSignatures(@import("jdk_internal_util_SystemProps.zig"));
}

pub const JniMethod = struct {
    method: []const u8,
    desc: []const u8,
};

fn validateFunctionSignatures(comptime module: type) void {
    @setEvalBranchQuota(10000);
    const std = @import("std");
    const sys = @import("jvm").jni.sys;

    // method names and descriptors declared
    const descriptors = @field(module, "methods");

    // discovered functions
    const decls = @typeInfo(module).Struct.decls;

    // array of decls visited and declared in `methods`
    var visited: [decls.len]bool = .{false} ** decls.len;

    inline for (descriptors) |m| {
        // TODO when comptime allocators work, compute mangled native name
        const class_name = blk: {
            const name = @typeName(module);
            break :blk name[0 .. name.len - 4]; // .zig
        };
        _ = class_name;

        // lookup in decls
        const decl = for (decls) |d, i| {
            if (std.mem.eql(u8, d.name, m.method)) break .{ .idx = i, .method = @field(module, m.method) };
        } else {
            // TODO generate a panicking stub instead
            continue;
            // @compileError("missing method decl " ++ @typeName(module) ++ "." ++ m.method);
        };

        const method_info = @typeInfo(@TypeOf(decl.method));

        const expected_return_type = m.desc[std.mem.lastIndexOfScalar(u8, m.desc, ')').? + 1];
        const actual_return_type = switch (method_info.Fn.return_type.?) {
            void => 'V',
            sys.jobject, sys.jclass => 'L',
            sys.jobjectArray => '[',
            sys.jboolean => 'Z',
            sys.jint => 'I',
            sys.jfloat => 'F',
            sys.jdouble => 'D',
            sys.jlong => 'J',
            else => @compileError("TODO ret type " ++ @typeName(method_info.Fn.return_type.?)),
        };

        if (actual_return_type != expected_return_type) {
            var expected: [1]u8 = .{expected_return_type};
            var actual: [1]u8 = .{actual_return_type};
            @compileError("method return type mismatch on " ++ @typeName(module) ++ "." ++ m.method ++ ": expected " ++ expected ++ " but found " ++ actual);
        }

        visited[decl.idx] = true;
    }

    // find undeclared methods
    for (decls) |d, i|
        if (std.mem.startsWith(u8, d.name, "Java_") and !visited[i])
            @compileError("native method must be declared in `methods`: " ++ @typeName(module) ++ "." ++ d.name);
}
