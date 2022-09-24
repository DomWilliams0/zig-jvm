const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const Allocator = std.mem.Allocator;
const Field = cafebabe.Field;

const LayoutDefinition = struct {};

pub const FieldId = struct { offset: u16 };

/// Updates layout_offset in each field
fn defineObjectLayout(alloc: Allocator, fields: []Field) !void {
    // TODO pass class loading arena alloc in instead

    // sort types into reverse size order
    var sorted_fields = try alloc.alloc(*Field, fields.len);
    defer alloc.free(sorted_fields);
    for (fields) |_, i| {
        sorted_fields[i] = &fields[i];
    }

    const helper = struct {
        fn cmpFieldDesc(context: void, a: *const Field, b: *const Field) bool {
            _ = context;
            const a_static = a.flags.contains(.static);
            const b_static = b.flags.contains(.static);

            return if (a_static != b_static)
                @boolToInt(a_static) < @boolToInt(b_static) // non static first
            else
                a.descriptor.size() > b.descriptor.size(); // larger first
        }
    };
    std.sort.insertionSort(*const Field, sorted_fields, {}, helper.cmpFieldDesc);

    // track offsets of each field (maximum 2^16 as stated in class file spec)
    var instance_offset: u16 = 0; // TODO start at superclass offset
    var static_offset: u16 = 0; // TODO start at superclass offset
    std.debug.assert(fields.len <= 65535); // TODO include super class field count too

    for (sorted_fields) |f| {
        const size = f.descriptor.size();
        var offset_ref = if (f.flags.contains(.static)) &static_offset else &instance_offset;

        var offset = offset_ref.*;
        offset = std.mem.alignForwardGeneric(u16, offset, size);
        f.layout_offset = offset;
        std.log.debug(" {s} {s} at offset {d}", .{ f.descriptor.str, f.name, offset });
        offset += size;

        offset_ref.* = offset;
    }
}

fn lookupFieldId(fields: []const Field, name: []const u8, desc: []const u8, flags: std.EnumSet(Field.Flags), antiflags: std.EnumSet(Field.Flags)) ?FieldId {
    for (fields) |f| {
        if ((f.flags.bits.mask & flags.bits.mask) == flags.bits.mask and
            (f.flags.bits.mask & ~(antiflags.bits.mask)) == f.flags.bits.mask and
            std.mem.eql(u8, desc, f.descriptor.str) and std.mem.eql(u8, name, f.name))
        {
            return .{ .offset = f.layout_offset };
        }
    }

    return null;
}

test "layout" {
    std.testing.log_level = .debug;

    const helper = struct {
        const TestCtx = struct {
            name: []const u8,
            desc: []const u8,
            static: bool = false,
            public: bool = true,
        };
        fn mkTestField(ctx: TestCtx) cafebabe.Field {
            var flags = std.EnumSet(Field.Flags).init(.{});
            if (ctx.static) flags.insert(.static);
            flags.insert(if (ctx.public) .public else .private);
            return .{
                .name = ctx.name,
                .flags = flags,
                .descriptor = @import("descriptor.zig").FieldDescriptor.new(ctx.desc) orelse unreachable,
                .attributes = std.ArrayListUnmanaged(cafebabe.Attribute).initCapacity(std.testing.allocator, 0) catch unreachable,
            };
        }

        fn mkFlags(flags: std.enums.EnumFieldStruct(Field.Flags, bool, false)) std.EnumSet(Field.Flags) {
            return std.EnumSet(Field.Flags).init(flags);
        }
    };

    var fields = [_]cafebabe.Field{
        helper.mkTestField(.{ .name = "myInt", .desc = "I" }),
        helper.mkTestField(.{ .name = "myInt2", .desc = "I" }),
        helper.mkTestField(.{ .name = "myInt3", .desc = "I" }),
        helper.mkTestField(.{ .name = "myDouble", .desc = "D" }),
        helper.mkTestField(.{ .name = "myLong", .desc = "J" }),
        helper.mkTestField(.{ .name = "myBool", .desc = "Z" }),
        helper.mkTestField(.{ .name = "myBoolStatic", .desc = "Z", .static = true }),
        helper.mkTestField(.{ .name = "myBool2", .desc = "Z" }),
        helper.mkTestField(.{ .name = "myString", .desc = "Ljava/lang/String;" }),
        helper.mkTestField(.{ .name = "myObjectStatic", .desc = "Ljava/lang/Object;", .static = true }),
        helper.mkTestField(.{ .name = "myArray", .desc = "[Ljava/lang/Object;" }),
        helper.mkTestField(.{ .name = "myArrayPrivate", .desc = "[Ljava/lang/Object;", .public = false }),
    };

    try defineObjectLayout(std.testing.allocator, &fields);

    // instance
    try std.testing.expect(lookupFieldId(&fields, "myInt3", "J", .{}, .{}) == null); // wrong type
    try std.testing.expect(lookupFieldId(&fields, "myInt3", "I", helper.mkFlags(.{ .private = true }), .{}) == null); // wrong visiblity
    try std.testing.expect(lookupFieldId(&fields, "myInt3", "I", .{}, helper.mkFlags(.{ .public = true })) == null); // antiflag
    const int3 = lookupFieldId(&fields, "myInt3", "I", helper.mkFlags(.{ .public = true }), helper.mkFlags(.{ .private = true })) orelse unreachable;
    try std.testing.expect(int3.offset > 0);
    try std.testing.expect(int3.offset % 4 == 0); // aligned

    // static
    const staticBool = lookupFieldId(&fields, "myBoolStatic", "Z", .{}, .{}) orelse unreachable;
    try std.testing.expect(staticBool.offset > 0);
}
