const std = @import("std");

pub const DataType = enum(u4) {
    boolean = 0,
    byte,
    short,
    int,
    long,
    char,
    float,
    double,
    reference,
    void,
    returnAddress,

    pub fn isPrimitive(self: @This()) bool {
        return switch (self) {
            .boolean, .byte, .short, .int, .long, .char, .float, .double => true,
            else => false,
        };
    }

    pub fn fromName(name: []const u8, comptime primitives_only: bool) ?DataType {
        return inline for (@typeInfo(@This()).Enum.fields) |field| {
            const val = @intToEnum(@This(), field.value);
            if (!primitives_only or val.isPrimitive())
                if (std.mem.eql(u8, name, field.name))
                    break val;
        } else null;
    }

    pub fn fromType(ty: []const u8) ?DataType {
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

    pub fn size(self: @This()) u8 {
        return switch (self) {
            .boolean, .byte => 1,
            .char, .short => 2,
            .float, .int => 4,
            .double, .long => 8,
            .reference => @sizeOf(usize),
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
            .reference => *void,
            else => @compileError("no corresponding type"),
        };
    }
};

const Primitive = struct {
    name: []const u8,
    ty: DataType,
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
