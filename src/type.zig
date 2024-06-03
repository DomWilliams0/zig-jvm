const std = @import("std");
const object = @import("object.zig");

pub const PrimitiveDataType = enum(u3) {
    boolean = 0,
    byte = 1,
    short = 2,
    int = 3,
    long = 4,
    char = 5,
    float = 6,
    double = 7,

    pub fn toDataType(self: @This()) DataType {
        return @enumFromInt(@intFromEnum(self));
    }

    pub fn size(self: @This()) u8 {
        return switch (self) {
            .boolean => 1,
            .byte => 1,
            .short => 2,
            .char => 2,
            .int => 4,
            .long => 8,
            .float => 4,
            .double => 8,
        };
    }

    pub fn alignment(self: @This()) u8 {
        return switch (self) {
            .boolean => @alignOf(bool),
            .byte => @alignOf(i8),
            .short => @alignOf(i16),
            .char => @alignOf(u16),
            .int => @alignOf(i32),
            .long => @alignOf(u64),
            .float => @alignOf(f32),
            .double => @alignOf(f64),
        };
    }

    pub fn fromTypeString(ty: []const u8) ?PrimitiveDataType {
        const c = if (ty.len == 0) return null else ty[0];
        return switch (c) {
            'B' => .byte,
            'Z' => .boolean,
            'C' => .char,
            'S' => .short,
            'I' => .int,
            'F' => .float,
            'D' => .double,
            'J' => .long,
            else => null,
        };
    }
};

pub const DataType = enum(u4) {
    boolean = 0,
    byte = 1,
    short = 2,
    int = 3,
    long = 4,
    char = 5,
    float = 6,
    double = 7,
    reference,
    void,
    returnAddress,

    pub fn isPrimitive(self: @This()) bool {
        return switch (self) {
            .boolean, .byte, .short, .int, .long, .char, .float, .double => true,
            else => false,
        };
    }

    pub fn asPrimitive(self: @This()) ?PrimitiveDataType {
        return switch (self) {
            .boolean, .byte, .short, .int, .long, .char, .float, .double => @enumFromInt(@intFromEnum(self)),
            else => null,
        };
    }

    pub fn fromName(name: []const u8, comptime primitives_only: bool) ?DataType {
        return inline for (@typeInfo(@This()).Enum.fields) |field| {
            const val: @This() = @enumFromInt(field.value);
            if (!primitives_only or val.isPrimitive())
                if (std.mem.eql(u8, name, field.name))
                    break val;
        } else null;
    }

    pub fn isWide(self: @This()) bool {
        return self == .long or self == .double;
    }

    pub fn size(self: @This()) u8 {
        return switch (self) {
            .boolean, .byte => 1,
            .char, .short => 2,
            .float, .int => 4,
            .double, .long => 8,
            .reference => @sizeOf(object.VmObjectRef.Nullable),
            .returnAddress => 4,
            else => 0,
        };
    }

    pub fn alignment(self: @This()) usize {
        return switch (self) {
            .boolean => @alignOf(bool),
            .byte => @alignOf(i8),
            .short => @alignOf(i16),
            .char => @alignOf(u16),
            .int => @alignOf(i32),
            .long => @alignOf(u64),
            .float => @alignOf(f32),
            .double => @alignOf(f64),
            .reference => @alignOf(usize),
            .returnAddress => @alignOf(u32),
            else => 0,
        };
    }

    pub fn asType(comptime self: @This()) type {
        return switch (self) {
            .boolean => bool,
            .byte => i8,
            .short => i16,
            .int => i32,
            .long => i64,
            .char => i16,
            .float => f32,
            .double => f64,
            .reference => object.VmObjectRef.Nullable,
            else => @compileError("no corresponding type"),
        };
    }

    pub fn fromType(comptime T: type) @This() {
        return switch (T) {
            bool => .boolean,
            i8 => .byte,
            i16 => .short,
            i32 => .int,
            i64 => .long,
            u16 => .char,
            f32 => .float,
            f64 => .double,
            object.VmObjectRef.Nullable => .reference,
            object.VmObjectRef => @compileError("use Nullable reference instead"),
            else => @compileError("invalid type " ++ @typeName(T)),
        };
    }
};

const Primitive = struct {
    name: []const u8,
    ty: PrimitiveDataType,
};
pub const primitives: [8]Primitive = .{
    .{ .name = "boolean", .ty = .boolean },
    .{ .name = "byte", .ty = .byte },
    .{ .name = "short", .ty = .short },
    .{ .name = "int", .ty = .int },
    .{ .name = "long", .ty = .long },
    .{ .name = "char", .ty = .char },
    .{ .name = "float", .ty = .float },
    .{ .name = "double", .ty = .double },
};

test "primitives" {
    try std.testing.expectEqual(primitives.len, 8);

    try std.testing.expectEqual(DataType.fromName("long", true).?, .long);
    try std.testing.expect(DataType.fromName("nah", true) == null);
    try std.testing.expect(DataType.fromName("reference", true) == null);

    try std.testing.expect(DataType.fromName("reference", false) != null);
}
