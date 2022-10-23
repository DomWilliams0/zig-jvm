const std = @import("std");
const object = @import("object.zig");
const state = @import("state.zig");
const classloader = @import("classloader.zig").ClassLoader;

/// Might intern strings one day
pub const StringPool = struct {
    global: *state.GlobalState,

    /// Only null until post bootstrap init
    java_lang_String: object.VmClassRef.Nullable,
    /// Only null until post bootstrap init
    byte_array: object.VmClassRef.Nullable,

    /// Undefined until post bootstrap init
    field_value: object.FieldId = undefined,

    pub fn new(global: *state.GlobalState) @This() {
        return .{ .global = global, .java_lang_String = object.VmClassRef.Nullable.nullRef(), .byte_array = object.VmClassRef.Nullable.nullRef() };
    }

    /// String class must be loaded by now
    pub fn postBootstrapInit(self: *@This()) void {
        const cls_ref = self.global.classloader.getLoadedBootstrapClass("java/lang/String") orelse @panic("java/lang/String is not loaded");
        self.java_lang_String = cls_ref.clone().intoNullable();
        const byte_array_ref = self.global.classloader.getLoadedBootstrapClass("[B") orelse @panic("[B is not loaded");
        self.byte_array = byte_array_ref.clone().intoNullable();

        // enforce utf16 encoding always
        const field = cls_ref.get().findFieldRecursively("COMPACT_STRINGS", "Z", .{ .static = true }) orelse @panic("missing COMPACT_STRINGS field on String");
        object.VmClass.getStaticField(bool, field.id).* = false;
        std.log.debug("set java/lang/String.COMPACT_STRINGS to false, will only use utf16 encoding", .{});

        self.field_value = (cls_ref.get().findFieldRecursively("value", "[B", .{ .static = false }) orelse @panic("missing value field")).id;
    }

    fn stringClass(self: @This()) object.VmClassRef {
        return self.java_lang_String.toStrongUnchecked();
    }

    pub fn getString(self: *@This(), bytes: []const u8) error{OutOfMemory}!object.VmObjectRef {
        const obj = try object.VmClass.instantiateObject(self.stringClass());

        // init byte array
        const value = try object.VmClass.instantiateArray(self.byte_array.toStrongUnchecked(), bytes.len);
        std.mem.copy(u8, value.get().getArrayHeader().getElems(u8), bytes);

        // set value field
        obj.get().getField(object.VmObjectRef, self.field_value).* = value;
        // no need to set coder field, it is always UTF16
        // TODO encode utf16 then!

        std.log.debug("created new string {?} with value '{s}'", .{ obj, bytes });
        return obj;
    }
};
