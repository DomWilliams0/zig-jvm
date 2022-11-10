const std = @import("std");
const types = @import("type.zig");

// TODO intern all types of descriptors, could store borrowed tag in last bit(s) of ptr
pub const FieldDescriptor = struct {
    // Must be validated with new
    str: []const u8,

    pub fn new(str: []const u8) ?FieldDescriptor {
        if (str.len == 0) return null;
        const extracted = extractFromStream(str) orelse return null;

        // no trailing chars allowed
        if (extracted.array_dims + extracted.ty.len != str.len) return null;

        return FieldDescriptor{ .str = str };
    }

    fn extractFromStream(str: []const u8) ?struct { ty: []const u8, array_dims: u8 } {
        std.debug.assert(str.len > 0);

        // count array dimensions
        const array_dims = blk: {
            for (str) |c, i| {
                if (c != '[') break :blk i;
            }
            break :blk 0;
        };

        if (array_dims > 255) return null;
        const ty = extractTy(str[array_dims..]) orelse return null;
        return .{ .ty = ty, .array_dims = @truncate(u8, array_dims) };
    }

    fn extractFromStreamTrusted(str: []const u8) []const u8 {
        // count array dimensions
        const array_dims = blk: {
            for (str) |c, i| {
                if (c != '[') break :blk i;
            }
            break :blk 0;
        };

        const ty = extractTy(str[array_dims..]).?;
        return str[0 .. array_dims + ty.len];
    }

    /// Should not be an array
    fn extractTy(str: []const u8) ?[]const u8 {
        return switch (str[0]) {
            'B',
            'C',
            'D',
            'F',
            'I',
            'J',
            'S',
            'Z',
            => str[0..1],
            'L' => if (std.mem.indexOfScalar(u8, str[1..], ';')) |idx| str[0 .. idx + 2] else null,
            else => null,
        };
    }

    pub fn size(self: @This()) u8 {
        return switch (self.str[0]) {
            'B', 'Z' => 1,
            'C', 'S' => 2,
            'F', 'I' => 4,
            'D', 'J' => 8,
            'L', '[' => @sizeOf(usize),
            else => unreachable,
        };
    }

    pub fn isWide(self: @This()) bool {
        return switch (self.str[0]) {
            'D', 'J' => true,
            else => false,
        };
    }

    pub fn getType(self: @This()) union(enum) {
        primitive: types.PrimitiveDataType,
        reference: []const u8,
        array: []const u8,
    } {
        return switch (self.str[0]) {
            'B' => .{ .primitive = .byte },
            'C' => .{ .primitive = .char },
            'D' => .{ .primitive = .double },
            'F' => .{ .primitive = .float },
            'I' => .{ .primitive = .int },
            'J' => .{ .primitive = .long },
            'S' => .{ .primitive = .short },
            'Z' => .{ .primitive = .boolean },
            'L' => .{ .reference = self.str[1 .. self.str.len - 1] },
            '[' => .{ .array = self.str[1..] },
            else => unreachable, // verified
        };
    }
};

pub const MethodDescriptor = struct {
    // Must be validated with new
    str: []const u8,

    /// Does not include `this` parameter for instance methods
    param_count: u8,

    pub fn new(str: []const u8) ?MethodDescriptor {
        if (str.len < 3 or str[0] != '(') {
            return null;
        }

        var idx: usize = 1;
        var count: u8 = 0;
        while (str[idx] != ')') {
            const ty = FieldDescriptor.extractFromStream(str[idx..]) orelse return null;
            idx += ty.array_dims + ty.ty.len;
            if (@addWithOverflow(u8, count, 1, &count)) return null; // too many args
        }

        idx += 1; // skip past )
        if (idx >= str.len) return null;

        // return type with no trailing chars
        if (!(str.len - 1 == idx and str[idx] == 'V')) {
            const ret = FieldDescriptor.new(str[idx..]) orelse return null;
            _ = ret;
        }

        return .{ .str = str, .param_count = count };
    }

    /// Returns null if void
    pub fn returnType(self: @This()) ?[]const u8 {
        if (!self.isNotVoid()) return null;

        const ret_start = std.mem.lastIndexOfScalar(u8, self.str, ')').?; // verified
        return self.str[ret_start + 1 ..];
    }

    pub fn returnTypeSimple(self: @This()) types.DataType {
        return switch (self.str[self.str.len - 1]) {
            'V' => .void,
            'B' => .byte,
            'C' => .char,
            'D' => .double,
            'F' => .float,
            'I' => .int,
            'J' => .long,
            'S' => .short,
            'Z' => .boolean,
            else => .reference,
        };
    }

    pub fn isNotVoid(self: @This()) bool {
        return self.str[self.str.len - 1] != 'V';
    }

    pub fn parameters(self: @This()) []const u8 {
        const end = std.mem.lastIndexOfScalar(u8, self.str, ')') orelse unreachable; // verified
        return self.str[1..end];
    }

    pub const ParamIterator = struct {
        str: []const u8,
        idx: usize = 0,

        pub fn next(self: *@This()) ?FieldDescriptor {
            if (self.str[self.idx] == ')') return null; // done

            const ty = FieldDescriptor.extractFromStreamTrusted(self.str[self.idx..]);
            self.idx += ty.len;
            return .{ .str = ty };
        }
    };
    pub fn iterateParamTypes(self: @This()) ParamIterator {
        return ParamIterator{ .str = self.str[1..] };
    }
};

test "valid field descriptors" {
    const valids = [_][]const u8{
        "S",
        "I",
        "Lnice;",
        "[[[Ljava/lang/String;",
        "[J",
    };
    const invalids = [_][]const u8{
        "Soon",
        "",
        "nice",
        "Ljava/lang/String;oops",
        "[",
        "[baa",
    };

    inline for (valids) |s|
        std.testing.expect(FieldDescriptor.new(s) != null) catch {
            std.log.err("invalid: {s}", .{s});
            unreachable;
        };

    inline for (invalids) |s|
        std.testing.expect(FieldDescriptor.new(s) == null) catch {
            std.log.err("should be invalid: {s}", .{s});
            unreachable;
        };
}

test "valid method descriptors" {
    const valids = [_][]const u8{ "()I", "(I)V", "(Lnice;[Z)Ljava/lang/String;", "(IDLjava/lang/Thread;)Ljava/lang/Object;" };
    const invalids = [_][]const u8{ "Soon", "", "(V", "(I)", "()Vcool", "([)V", "(IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII)V" };

    inline for (valids) |s|
        std.testing.expect(MethodDescriptor.new(s) != null) catch {
            std.log.err("invalid: {s}", .{s});
            unreachable;
        };

    inline for (invalids) |s|
        std.testing.expect(MethodDescriptor.new(s) == null) catch {
            std.log.err("should be invalid: {s}", .{s});
            unreachable;
        };

    try std.testing.expect(MethodDescriptor.new("()V").?.returnType() == null);
    try std.testing.expectEqualStrings("I", MethodDescriptor.new("()I").?.returnType().?);
    try std.testing.expectEqualStrings("Ljava/lang/Object;", MethodDescriptor.new("(IDLjava/lang/Thread;)Ljava/lang/Object;").?.returnType().?);

    const desc = MethodDescriptor.new("(IDLjava/lang/Thread;)Ljava/lang/Object;").?;
    try std.testing.expectEqual(@as(u8, 3), desc.param_count);
    var params = desc.iterateParamTypes();
    try std.testing.expectEqualStrings("I", params.next().?);
    try std.testing.expectEqualStrings("D", params.next().?);
    try std.testing.expectEqualStrings("Ljava/lang/Thread;", params.next().?);
    try std.testing.expect(params.next() == null);
}

test "getType" {
    const S = struct {
        fn check(desc: []const u8, expected: @typeInfo(@TypeOf(FieldDescriptor.getType)).Fn.return_type.?) !void {
            const ty = FieldDescriptor.new(desc).?.getType();

            try switch (expected) {
                .primitive => std.testing.expectEqual(ty, expected),
                .array => |s| std.testing.expectEqualStrings(s, ty.array),
                .reference => |s| std.testing.expectEqualStrings(s, ty.reference),
            };
        }
    };
    try S.check("I", .{ .primitive = .int });
    try S.check("Ljava/lang/String;", .{ .reference = "java/lang/String" });
    try S.check("[S", .{ .array = "S" });
    try S.check("[[I", .{ .array = "[I" });
}
