const std = @import("std");
const object = @import("object.zig");
const descriptor = @import("descriptor.zig");
const types = @import("type.zig");
const frame = @import("frame.zig");
const state = @import("state.zig");

pub const libffi = @cImport({
    @cInclude("ffi.h");
});

fn typeToFfi(ty: types.DataType) [*c]libffi.ffi_type {
    return switch (ty) {
        .void => &libffi.ffi_type_void,
        .boolean, .byte => &libffi.ffi_type_sint8,
        .short => &libffi.ffi_type_sint16,
        .int => &libffi.ffi_type_sint32,
        .long => &libffi.ffi_type_sint64,
        .char => &libffi.ffi_type_uint16,
        .float => &libffi.ffi_type_float,
        .double => &libffi.ffi_type_double,
        .reference => &libffi.ffi_type_pointer,
        .returnAddress => unreachable,
    };
}

fn typeCharToFfi(ty: []const u8) [*c]libffi.ffi_type {
    return switch (ty[0]) {
        'V' => &libffi.ffi_type_void,
        'B', 'Z' => &libffi.ffi_type_sint8,
        'S' => &libffi.ffi_type_sint16,
        'I' => &libffi.ffi_type_sint32,
        'J' => &libffi.ffi_type_sint64,
        'C' => &libffi.ffi_type_uint16,
        'F' => &libffi.ffi_type_float,
        'D' => &libffi.ffi_type_double,
        else => &libffi.ffi_type_pointer,
    };
}

pub const NativeMethodCode = struct {
    cif: libffi.ffi_cif,
    arg_types: [][*c]libffi.ffi_type,
    /// Same len as arg_types
    args: [*]*const anyopaque,
    ret_type: types.DataType,
    fn_ptr: *const anyopaque,

    pub fn new(alloc: std.mem.Allocator, desc: descriptor.MethodDescriptor, fn_ptr: anytype) state.Error!@This() {
        return newInner(alloc, desc, @ptrCast(*const anyopaque, fn_ptr));
    }

    fn newInner(alloc: std.mem.Allocator, desc: descriptor.MethodDescriptor, fn_ptr: *const anyopaque) state.Error!@This() {
        var cif: libffi.ffi_cif = undefined;

        const arg_count = desc.param_count + 2; // +jni table and cls/this

        var arg_types = try alloc.alloc([*c]libffi.ffi_type, arg_count);
        errdefer alloc.free(arg_types);
        var args = try alloc.alloc(*const anyopaque, arg_count);
        errdefer alloc.free(args);

        arg_types[0] = &libffi.ffi_type_pointer; // jni table
        arg_types[1] = &libffi.ffi_type_pointer; // cls/this

        var i: usize = 2;
        var arg_iter = desc.iterateParamTypes();
        while (arg_iter.next()) |it| {
            arg_types[i] = typeCharToFfi(it);
            i += 1;
        }
        const ret_type = desc.returnTypeSimple();
        const rtype = typeToFfi(ret_type);
        const ret = libffi.ffi_prep_cif(&cif, libffi.FFI_DEFAULT_ABI, arg_count, rtype, arg_types.ptr);
        if (ret != libffi.FFI_OK) {
            std.log.err("ffi_prep_cif failed: {d}", .{ret});
            return error.LibFfi;
        }

        return .{
            .cif = cif,
            .arg_types = arg_types,
            .args = args.ptr,
            .ret_type = ret_type,
            .fn_ptr = fn_ptr,
        };
    }

    fn peekArg(self: @This(), caller: *frame.Frame.OperandStack, idx: u16) *anyopaque {
        const peek_idx = @truncate(u16, self.arg_types.len) - idx - 1;

        return switch (self.arg_types[idx].*.type) {
            libffi.FFI_TYPE_SINT8 => caller.peekAtPtrFfi(i8, peek_idx),
            libffi.FFI_TYPE_SINT16 => caller.peekAtPtrFfi(i16, peek_idx),
            libffi.FFI_TYPE_SINT32 => caller.peekAtPtrFfi(i32, peek_idx),
            libffi.FFI_TYPE_SINT64 => caller.peekAtPtrFfi(i64, peek_idx),
            libffi.FFI_TYPE_UINT16 => caller.peekAtPtrFfi(u16, peek_idx),
            libffi.FFI_TYPE_FLOAT => caller.peekAtPtrFfi(f32, peek_idx),
            libffi.FFI_TYPE_DOUBLE => caller.peekAtPtrFfi(f64, peek_idx),
            libffi.FFI_TYPE_POINTER => caller.peekAtPtrFfi(object.VmObjectRef.Nullable, peek_idx),
            else => unreachable,
        };
    }

    pub fn invoke(self: *@This(), caller: *frame.Frame.OperandStack, static_class: ?object.VmObjectRef) void {
        // populate args with ptrs to caller stack
        var jnienv = &&state.thread_state().jni;
        self.args[0] = @ptrCast(*const anyopaque, jnienv);

        // 0 is already initialised to jni table ptr
        var i: u16 = if (static_class) |static| blk: {
            // class is arg 1
            self.args[1] = @ptrCast(*anyopaque, static.intoNullable().ptr);
            break :blk 2; // pop from arg 2
        } else 1; // pop from arg 1 which includes `this`

        while (i < self.arg_types.len) : (i += 1) {
            self.args[i] = self.peekArg(caller, i);
        }

        var ret_slot: usize = undefined;
        const func_ptr = @ptrCast(*const fn () callconv(.C) void, self.fn_ptr);
        libffi.ffi_call(@ptrCast([*c]libffi.ffi_cif, &self.cif), func_ptr, &ret_slot, @ptrCast([*c]?*anyopaque, self.args));

        // pop args
        var to_pop: usize = self.arg_types.len - 1; // don't pop for jni table arg
        if (static_class != null) to_pop -= 1; // don't pop for static class arg
        if (to_pop > 0) std.log.debug("popping {d} args from caller stack", .{to_pop});
        while (to_pop > 0) : (to_pop -= 1) _ = caller.popRaw();

        // push return value
        if (self.ret_type != .void) {
            const ret = frame.Frame.StackEntry{ .value = ret_slot, .ty = self.ret_type };
            // widen to integer like ireturn
            caller.pushRaw(switch (self.ret_type) {
                .boolean, .byte, .short, .int, .char => frame.Frame.StackEntry.new(ret.convertToInt()),
                else => ret,
            });
        }
    }

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        const args = self.args[0..self.arg_types.len]; // take len
        alloc.free(self.arg_types);
        alloc.free(args);
    }
};

test "libffi" {
    // std.testing.log_level = .debug;
    const S = struct {
        fn the_func(jni: *anyopaque, this: *anyopaque, int: i32, float: f32) callconv(.C) i32 {
            _ = jni;
            _ = this;

            std.testing.expect(int == 0x12345678) catch unreachable;
            std.testing.expect(float == 3.14) catch unreachable;

            return 123;
        }
    };

    // needed to provide thread jni env
    const handle = try @import("state.zig").ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    const desc = descriptor.MethodDescriptor.new("(IFJZSB)I").?;
    var native = NativeMethodCode.new(std.testing.allocator, desc, &S.the_func) catch unreachable;
    defer native.deinit(std.testing.allocator);

    var o_backing = [_]frame.Frame.StackEntry{frame.Frame.StackEntry.notPresent()} ** 16;
    var stack = frame.Frame.OperandStack.new(&o_backing);

    stack.push(object.VmObjectRef.Nullable.nullRef()); // this
    stack.push(@as(i32, 0x12345678));
    stack.push(@as(f32, 3.14));
    stack.push(@as(i64, 0x12121212_24242424));
    stack.push(@as(bool, true));
    stack.push(@as(i16, -1024));
    stack.push(@as(i8, 105));

    native.invoke(&stack, null);
    try std.testing.expectEqual(@as(i32, 123), stack.pop(i32));
}
