const std = @import("std");
const classloader = @import("classloader.zig");
const vm_alloc = @import("alloc.zig");
const object = @import("object.zig");
const interp = @import("interpreter.zig");
const state = @import("state.zig");
const string = @import("string.zig");

const Allocator = std.mem.Allocator;
const StackEntry = @import("frame.zig").Frame.StackEntry;
const Error = state.Error;

pub fn initWithDefaultConstructor(thread: *state.ThreadEnv, cls: object.VmClassRef) Error!object.VmObjectRef {
    const obj = try object.VmClass.instantiateObject(cls);
    return runMethod(thread, cls, "<init>", "()V", .{obj});
}

/// Returns NoClassDefError if method not found, otherwise InternalError if it fails
pub fn runMethod(thread: *state.ThreadEnv, cls: object.VmClassRef, name: []const u8, desc: []const u8, args: anytype) Error!StackEntry {
    const method = cls.get().findMethodRecursive(name, desc) orelse return state.makeError(error.NoSuchMethod, state.MethodDescription{ .cls = cls.get().name, .method = name, .desc = desc });

    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct or !args_type_info.Struct.is_tuple) {
        @compileError("expected tuple argument, found " ++ @typeName(ArgsType));
    }

    const arg_count = args_type_info.Struct.fields.len;
    const expected_count = method.descriptor.param_count + (if (!method.flags.contains(.static)) @as(u8, 1) else 0);
    if (arg_count != expected_count) {
        std.log.err("expected {d} params for {?} but got {d}", .{ expected_count, method, arg_count });
        return state.makeError(error.Internal, "wrong number of arguments");
    }

    var method_args: [arg_count]StackEntry = undefined;
    inline for (std.meta.fields(ArgsType)) |_, i| {
        const field_name = comptime std.fmt.comptimePrint("{}", .{i});
        const val = @field(args, @as([]const u8, field_name));
        method_args[i] = StackEntry.new(val);
    }

    return (thread.interpreter.executeUntilReturnWithArgs(method, method_args.len, method_args) catch |ex| {
        if (method.flags.contains(.static))
            std.log.warn("failed to run {?}: {any}", .{ method, ex })
        else
            std.log.warn("failed to run {?} on {?}: {any}", .{ method, method_args[0], ex });
        return state.makeError(error.Internal, method);
    }) orelse {
        if (method.flags.contains(.static))
            std.log.warn("failed to run {?}: {?}", .{ method, thread.interpreter.exception().toStrongUnchecked() })
        else
            std.log.warn("failed to run {?} on {?}: {?}", .{ method, method_args[0], thread.interpreter.exception().toStrongUnchecked() });
        return state.makeError(error.Internal, method);
    };
}

pub fn setField(obj: object.VmObjectRef, name: []const u8, desc: []const u8, val: anytype) Error!void {
    const cls = obj.get().class;
    const field = cls.get().findFieldRecursively(name, desc, .{ .static = false }) orelse return state.makeError(error.NoSuchField, state.MethodDescription{ .cls = cls.get().name, .method = name, .desc = desc });
    const field_value = obj.get().getField(@TypeOf(val), field.id);
    field_value.* = val;
    std.log.debug("set field {?}.{s} = {any}", .{ obj, name, val });
}

pub fn setStaticField(cls: object.VmClassRef, name: []const u8, val: anytype) Error!void {
    // TODO func for this
    const val_ty = @TypeOf(val);
    const desc = switch (val_ty) {
        i32 => "I",
        bool => "Z",
        else => @compileError("bad value type"),
    };

    const field = cls.get().findFieldRecursively(name, desc, .{ .static = true }) orelse return state.makeError(error.NoSuchField, state.MethodDescription{ .cls = cls.get().name, .method = name, .desc = desc });
    const field_value = object.VmClass.getStaticField(val_ty, field.id);
    field_value.* = val;
    std.log.debug("set static field {s}.{s} = {any}", .{ cls.get().name, name, val });
}

pub fn getStaticField(cls: object.VmClassRef, name: []const u8, comptime T: type) Error!T {
    // TODO func for this
    const desc = switch (T) {
        i32 => "I",
        bool => "Z",
        else => @compileError("bad value type"),
    };

    const field = cls.get().findFieldRecursively(name, desc, .{ .static = true }) orelse return state.makeError(error.NoSuchField, state.MethodDescription{ .cls = cls.get().name, .method = name, .desc = desc });
    return object.VmClass.getStaticField(T, field.id).*;
}

pub fn getStaticFieldInfallible(cls: object.VmClassRef, name: []const u8, comptime T: type) T {
    return getStaticField(cls, name, T) catch std.debug.panic("class {s} does not have expected field {s}", .{ cls.get().name, name });
}

pub fn setFieldInfallible(obj: object.VmObjectRef, name: []const u8, desc: []const u8, val: anytype) void {
    setField(obj, name, desc, val) catch std.debug.panic("object {?} does not have expected field {s}", .{ obj, name });
}

pub fn setStaticFieldInfallible(cls: object.VmClassRef, name: []const u8, val: anytype) void {
    setStaticField(cls, name, val) catch std.debug.panic("class {s} does not have expected field {s}", .{ cls.get().name, name });
}

/// "$what threw exception ..."
pub fn logExceptionWithCause(thread: *state.ThreadEnv, what: []const u8, exc: object.VmObjectRef) void {
    const exc_str = object.ToString.new_with_exc_cause(thread.global.allocator.inner, exc);
    defer exc_str.deinit();
    std.log.err("{s} threw exception {?}: \"{s}\"", .{ what, exc, exc_str.exc.str });
    for (exc_str.causes.items) |cause|
        std.log.err(" caused by: \"{s}\"", .{cause.str});
}
