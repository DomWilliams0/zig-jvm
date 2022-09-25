const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const vm_type = @import("type.zig");
const Allocator = std.mem.Allocator;
const Field = cafebabe.Field;

/// Always allocated on GC heap
pub const VmClass = struct {
    constant_pool: cafebabe.ConstantPool, // TODO will be tweaked at runtime when refs are resolved
    flags: std.EnumSet(cafebabe.ClassFile.Flags),
    /// Owned copy
    name: []const u8,
    // /// Owned copy
    // super_name: ?[]const u8,
    super_cls: ?VmClassRef,
    interfaces: []*VmClass, // TODO class refs

    /// Only fields for this class
    fields: []Field,
    // TODO methods
    attributes: []const cafebabe.Attribute,
    // TODO vmdata field

    layout: union {
        /// Exact size of the object, including all headers and storage
        fields: ObjectLayout,

        primitive: vm_type.DataType,

        // TODO array elem type
    },

    // ---------- VmRef interface
    pub fn vmRefSize(_: *const VmClass) usize {
        return 0; // nothing extra
    }
    pub fn vmRefDrop(_: @This()) void {
        // TODO release owned memory
    }

    // ---------- field accessors
    // TODO expose generic versions for each type instead
    pub fn getField(self: *@This(), comptime T: type, field: FieldId) *T {
        switch (field) {
            .instance_offset => |offset| {
                var byte_ptr: [*]u8 = @ptrCast([*]align(@alignOf(T)) u8, self);
                return @ptrCast(*T, byte_ptr + offset);
            },
            .static_index => |idx| {
                const ptr = &self.fields[idx].u.value;
                return @ptrCast(*T, ptr);
            },
        }
    }
};

/// Header for objects, variable sized based on class (array, fields, etc)
pub const VmObject = struct {
    class: *VmClass,
};

pub const VmClassRef = vm_alloc.VmRef(VmClass);
pub const VmObjectRef = vm_alloc.VmRef(VmObject);

pub const FieldId = union(enum) {
    /// Offset into obj storage
    instance_offset: u16,
    /// Index into fields slice
    static_index: u16,
};

pub const ObjectLayout = struct {
    instance_offset: u16 = @sizeOf(VmObject),
};

pub const WhichLoader = union(enum) {
    bootstrap,
    user: VmObjectRef,
};

/// Updates layout_offset in each field, offset from the given base. Updates to the offset after these fields
pub fn defineObjectLayout(alloc: Allocator, fields: []Field, base: *ObjectLayout) error{OutOfMemory}!void {
    // TODO pass class loading arena alloc in instead

    // sort types into reverse size order
    // TODO this depends on starting offset - if the last super class field is e.g. bool (1 aligned),
    //  we should shove as many fields into that space as possible
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
    var out_offset = base;
    std.debug.assert(fields.len <= 65535); // TODO include super class field count too

    for (sorted_fields) |f| {
        if (f.flags.contains(.static)) {
            // static values just live in the class directly
            f.u = .{ .value = 0 };
        } else {
            // instance
            const size = f.descriptor.size();
            out_offset.instance_offset = std.mem.alignForwardGeneric(u16, out_offset.instance_offset, size);
            f.u = .{ .layout_offset = out_offset.instance_offset };
            std.log.debug(" {s} {s} at offset {d}", .{ f.descriptor.str, f.name, out_offset.instance_offset });
            out_offset.instance_offset += size;
        }
    }
}

fn lookupFieldId(fields: []const Field, name: []const u8, desc: []const u8, flags: std.EnumSet(Field.Flags), antiflags: std.EnumSet(Field.Flags)) ?FieldId {
    for (fields) |f, i| {
        if ((f.flags.bits.mask & flags.bits.mask) == flags.bits.mask and
            (f.flags.bits.mask & ~(antiflags.bits.mask)) == f.flags.bits.mask and
            std.mem.eql(u8, desc, f.descriptor.str) and std.mem.eql(u8, name, f.name))
        {
            return if (f.flags.contains(.static)) .{ .static_index = @intCast(u16, i) } else .{ .instance_offset = f.u.layout_offset };
        }
    }

    return null;
}

// -- tests

fn test_helper() type {
    return struct {
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

        var fields = [_]cafebabe.Field{
            mkTestField(.{ .name = "myInt", .desc = "I" }),
            mkTestField(.{ .name = "myInt2", .desc = "I" }),
            mkTestField(.{ .name = "myInt3", .desc = "I" }),
            mkTestField(.{ .name = "myIntStatic", .desc = "I", .static = true }),
            mkTestField(.{ .name = "myDouble", .desc = "D" }),
            mkTestField(.{ .name = "myLong", .desc = "J" }),
            mkTestField(.{ .name = "myBool", .desc = "Z" }),
            mkTestField(.{ .name = "myBoolStatic", .desc = "Z", .static = true }),
            mkTestField(.{ .name = "myBool2", .desc = "Z" }),
            mkTestField(.{ .name = "myString", .desc = "Ljava/lang/String;" }),
            mkTestField(.{ .name = "myObjectStatic", .desc = "Ljava/lang/Object;", .static = true }),
            mkTestField(.{ .name = "myArray", .desc = "[Ljava/lang/Object;" }),
            mkTestField(.{ .name = "myArrayPrivate", .desc = "[Ljava/lang/Object;", .public = false }),
        };
    };
}

test "layout" {
    // std.testing.log_level = .debug;

    const helper = test_helper();
    var layout = ObjectLayout{};
    try defineObjectLayout(std.testing.allocator, &helper.fields, &layout);
    // try std.testing.expectEqual(layout.instance_offset, 54);
    // try std.testing.expectEqual(layout.static_offset, 9);

    // instance
    try std.testing.expect(lookupFieldId(&helper.fields, "myInt3", "J", .{}, .{}) == null); // wrong type
    try std.testing.expect(lookupFieldId(&helper.fields, "myInt3", "I", helper.mkFlags(.{ .private = true }), .{}) == null); // wrong visiblity
    try std.testing.expect(lookupFieldId(&helper.fields, "myInt3", "I", .{}, helper.mkFlags(.{ .public = true })) == null); // antiflag
    const int3 = lookupFieldId(&helper.fields, "myInt3", "I", helper.mkFlags(.{ .public = true }), helper.mkFlags(.{ .private = true })) orelse unreachable;
    try std.testing.expectEqual(@as(u16, 48 + @sizeOf(VmObject)), int3.instance_offset);

    // static
    _ = lookupFieldId(&helper.fields, "myBoolStatic", "Z", .{}, .{}) orelse unreachable;
}

test "allocate class" {
    // std.testing.log_level = .debug;
    const helper = test_helper();
    var alloc = std.testing.allocator;

    // init base class with no super
    var base_fields = [_]cafebabe.Field{
        helper.mkTestField(.{ .name = "baseInt", .desc = "I" }),
        helper.mkTestField(.{ .name = "baseStaticInt", .desc = "I", .static = true }),
    };
    var layout = ObjectLayout{}; // no super
    try defineObjectLayout(alloc, &base_fields, &layout);

    // now init class with this as its super
    try defineObjectLayout(alloc, &helper.fields, &layout);

    const int3 = lookupFieldId(&helper.fields, "myInt3", "I", helper.mkFlags(.{ .public = true }), helper.mkFlags(.{ .private = true })) orelse unreachable;
    try std.testing.expect(int3.instance_offset > 0 and int3.instance_offset % @alignOf(i32) == 0);

    // init global allocator
    const handle = try @import("jvm.zig").ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    // allocate class with static storage
    const cls = try vm_alloc.allocClass();
    cls.get().layout = layout; // everything is unintialised
    cls.get().fields = &helper.fields; // only instance fields, need to concat super and this fields together
    defer cls.drop();

    const static_int_val = cls.get().getField(i32, lookupFieldId(cls.get().fields, "myIntStatic", "I", .{}, .{}) orelse unreachable);
    static_int_val.* = 0x12345678;
}

test "vmref size" {
    try std.testing.expectEqual(@sizeOf(*u8), @sizeOf(VmObjectRef));
    try std.testing.expectEqual(@sizeOf(*u8), @sizeOf(VmObjectRef.Weak));
}
