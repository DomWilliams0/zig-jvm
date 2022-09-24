const std = @import("std");

// TODO intern all types of descriptors, could store borrowed tag in last bit(s) of ptr
pub const FieldDescriptor = struct {
    // Must be validated with new
    str: []const u8,

    pub fn new(str: []const u8) ?FieldDescriptor {
        if (str.len == 0) {
            return null;
        }

        // count array dimensions
        const array_dims = blk: {
            for (str) |c, i| {
                if (c != '[') break :blk i;
            }
            break :blk 0;
        };

        if (array_dims > 255) return null;
        const ty = extractTy(str[array_dims..]) orelse return null;

        // no trailing chars allowed
        if (array_dims + ty.len != str.len) return null;

        return FieldDescriptor{ .str = str };
    }

    /// Should not be an array
    fn extractTy(str: []const u8) ?[]const u8 {
        if (str.len == 1) {
            switch (str[0]) {
                'B',
                'C',
                'D',
                'F',
                'I',
                'J',
                'S',
                'Z',
                => return str[0..1],
                else => return null,
            }
        } else {
            if (str[0] != 'L') return null;
            if (std.mem.indexOfScalar(u8, str[1..], ';')) |idx| {
                return str[0 .. idx + 2];
            }
        }

        return null;
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
};

pub const MethodDescriptor = struct {
    // Must be validated with new
    str: []const u8,

    pub fn new(str: []const u8) ?MethodDescriptor {
        // TODO
        return .{ .str = str };
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
