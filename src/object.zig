const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const vm_type = @import("type.zig");
const classloader = @import("classloader.zig");
const Allocator = std.mem.Allocator;
const Field = cafebabe.Field;
const Method = cafebabe.Method;

/// Always allocated on GC heap
pub const VmClass = struct {
    constant_pool: cafebabe.ConstantPool,
    flags: std.EnumSet(cafebabe.ClassFile.Flags),
    name: []const u8, // constant pool reference
    super_cls: ?VmClassRef,
    interfaces: []*VmClass, // TODO class refs
    loader: classloader.WhichLoader,
    init_state: InitState = .uninitialised,
    monitor: Monitor = .{}, // TODO put into java.lang.Class object instance instead

    /// Only fields for this class
    u: union {
        /// Object class with fields
        obj: struct {
            fields: []Field,
            methods: []Method,
            layout: ObjectLayout,
        },
        primitive: vm_type.DataType,
        array: struct {
            elem_cls: VmClassRef,
            dims: u8,
        },
    },

    const InitState = union(enum) {
        uninitialised,
        initialising: std.Thread.Id,
        initialised,
        failed,
    };

    // TODO methods
    // attributes: []const cafebabe.Attribute,
    // TODO vmdata field

    // ---------- VmRef interface
    pub fn vmRefSize(_: *const VmClass) usize {
        return 0; // nothing extra
    }
    pub fn vmRefDrop(_: *@This()) void {
        // TODO release owned memory
    }

    // ---------- field accessors
    // TODO expose generic versions for each type instead
    pub fn getField(self: *@This(), comptime T: type, field: FieldId) *T {
        switch (field) {
            .instance_offset => |offset| {
                var byte_ptr: [*]u8 = @ptrCast([*]u8, self);
                return @ptrCast(*T, @alignCast(@alignOf(T), byte_ptr + offset));
            },
            .static_index => |idx| {
                const ptr = &self.u.obj.fields[idx].u.value;
                return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
            },
        }
    }

    /// Looks in superclasses and interfaces (5.4.3.3. Method Resolution)
    pub fn findMethodRecursive(self: @This(), name: []const u8, desc: []const u8) ?*const Method {

        // TODO if signature polymorphic, resolve class names mentioned in descriptor too

        // check self and supers recursively first
        if (self.findMethodInSelfOrSupers(name, desc)) |m| return m;

        // check superinterfaces
        @panic("TODO find method in super interfaces");
    }

    fn findMethodInSelfOrSupers(
        self: @This(),
        name: []const u8,
        desc: []const u8,
    ) ?*const Method {
        // check self
        if (self.findMethodInThisOnly(name, desc, .{})) |m| return m;

        // check super recursively
        return if (self.super_cls) |super| super.get().findMethodRecursive(name, desc) else null;
    }

    pub fn findMethodInThisOnly(
        self: @This(),
        name: []const u8,
        desc: []const u8,
        flags: anytype,
    ) ?*const Method {
        const pls = makeFlagsAndAntiFlags(Method.Flags, flags);
        return for (self.u.obj.methods) |m, i| {
            if ((m.flags.bits.mask & pls.flags.bits.mask) == pls.flags.bits.mask and
                (m.flags.bits.mask & ~(pls.antiflags.bits.mask)) == m.flags.bits.mask and
                std.mem.eql(u8, desc, m.descriptor.str) and std.mem.eql(u8, name, m.name))
            {
                // seems like returning &m is returning a function local...
                break &self.u.obj.methods[i];
            }
        } else null;
    }

    pub fn ensureInitialised(self: VmClassRef) void {
        var self_mut = self.get();
        {
            self_mut.monitor.mutex.lock();
            defer self_mut.monitor.mutex.unlock();

            const current_state = self_mut.init_state;
            switch (current_state) {
                .failed => {
                    // TODO exception
                    @panic("failed init");
                },
                .initialised => return,
                .initialising => |t| {
                    const this_thread = std.Thread.getCurrentId();
                    if (this_thread == t) {
                        // recursive
                        return;
                    }

                    // another thread is initialising, block
                    std.log.debug("another thread is already initialising {s}, blocking thread {d}", .{ self_mut.name, std.Thread.getCurrentId() });
                    while (self_mut.init_state != .initialising) {
                        self_mut.monitor.condition.wait(&self_mut.monitor.mutex);
                    }

                    std.log.debug("unblocked thread {d}", .{std.Thread.getCurrentId()});
                    return ensureInitialised(self); // recurse
                },
                .uninitialised => {
                    // do it now
                    self_mut.init_state = .{ .initialising = std.Thread.getCurrentId() };
                    std.log.debug("initialising class {s} on thread {d}", .{ self_mut.name, std.Thread.getCurrentId() });
                },
            }
        } // monitor dropped here

        // TODO set static field values from ConstantValue attrs

        // ensure superclass is initialised already
        if (!self_mut.flags.contains(.interface)) {
            if (self_mut.super_cls) |super| {
                // std.log.debug("initialising super class {s} on thread {d}", .{ super.get().name, std.Thread.getCurrentId() });
                ensureInitialised(super);
            }

            // TODO init super interfaces too
        }

        // run class constructor
        // TODO exception
        if (self_mut.findMethodInThisOnly("<clinit>", "()V", .{ .static = true })) |clinit| {
            @import("jvm.zig").thread_state().interpreter.executeUntilReturn(self, clinit) catch std.debug.panic("clinit failed", .{});
        }

        // set init state
        self_mut.monitor.mutex.lock();
        std.log.debug("initialised class {s}", .{self_mut.name});
        defer self_mut.monitor.mutex.unlock();

        // TODO might have errored
        self_mut.init_state = .initialised;
        self_mut.monitor.notifyAll();
    }
};

const Monitor = struct {
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},

    pub fn notifyAll(self: @This()) void {
        // TODO
        _ = self;
    }
};

/// Header for objects, variable sized based on class (array, fields, etc)
pub const VmObject = struct {
    class: *VmClass,

    // ---------- VmRef interface
    pub fn vmRefSize(_: *const VmObject) usize {
        return 0; // TODO
    }
    pub fn vmRefDrop(_: *@This()) void {
        // TODO
    }
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
    /// Exact offset to start of fields from start of object
    instance_offset: u16 = @sizeOf(VmObject),
};

/// Implicitly lives at the end of an object allocation that is an array
pub const ArrayStorageRef = extern struct {
    len: u32,
    // `len` elements go here

    fn elementsStart(self: *@This(), comptime T: type) []T {
        std.debug.assert(@sizeOf(T) != 0);
        // const padding = 0; // TODO

        const ptr: [*]u32 = &self.len;
        _ = ptr;
        unreachable;
    }

    pub fn getElementsShorts(self: *@This()) []i16 {
        _ = self;
    }
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

// fn defineArrayLayout(alloc: Allocator, fields: []Field, base: *ObjectLayout) error{OutOfMemory}!void {
//         // TODO multidim - nah ignore
//     }

// TODO pass enum field map instead of 2 sets
fn lookupFieldId(fields: []const Field, name: []const u8, desc: []const u8, input_flags: anytype) ?FieldId {
    const flags = makeFlagsAndAntiFlags(Field.Flags, input_flags);
    for (fields) |f, i| {
        if ((f.flags.bits.mask & flags.flags.bits.mask) == flags.flags.bits.mask and
            (f.flags.bits.mask & ~(flags.antiflags.bits.mask)) == f.flags.bits.mask and
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
            };
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
    try std.testing.expect(lookupFieldId(&helper.fields, "myInt3", "J", .{}) == null); // wrong type
    try std.testing.expect(lookupFieldId(&helper.fields, "myInt3", "I", .{ .private = true }) == null); // wrong visiblity
    try std.testing.expect(lookupFieldId(&helper.fields, "myInt3", "I", .{ .public = false }) == null); // antiflag
    const int3 = lookupFieldId(&helper.fields, "myInt3", "I", .{ .public = true, .private = false }) orelse unreachable;
    try std.testing.expectEqual(@as(u16, 48 + @sizeOf(VmObject)), int3.instance_offset);

    // static
    _ = lookupFieldId(&helper.fields, "myBoolStatic", "Z", .{}) orelse unreachable;
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

    const int3 = lookupFieldId(&helper.fields, "myInt3", "I", .{ .public = true, .private = false }) orelse unreachable;
    try std.testing.expect(int3.instance_offset > 0 and int3.instance_offset % @alignOf(i32) == 0);

    // init global allocator
    const handle = try @import("jvm.zig").ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    // allocate class with static storage
    const cls = try vm_alloc.allocClass();
    cls.get().u = .{ .obj = .{ .fields = &helper.fields, .layout = layout, .methods = undefined } }; // only instance fields, need to concat super and this fields together
    defer cls.drop();

    const static_int_val = cls.get().getField(i32, lookupFieldId(cls.get().u.obj.fields, "myIntStatic", "I", .{}) orelse unreachable);
    static_int_val.* = 0x12345678;
}

test "vmref size" {
    try std.testing.expectEqual(@sizeOf(*u8), @sizeOf(VmObjectRef));
    try std.testing.expectEqual(@sizeOf(*u8), @sizeOf(VmObjectRef.Weak));
}

test "array" {
    // var allocation: [32]u8 = .{0} ** 32;
    // // const backing = [6]i16{1,2,3,4,5,6};
    // var untyped_ref = @ptrCast(*ArrayStorageRef, &allocation[0]);
    // untyped_ref.len = 4;

    // const typed = ArrayStorageRef.specialised(.short);
    // var typed_ref = @ptrCast(*typed, &untyped_ref);

    // try std.testing.expectEqual(4, typed_ref.len);
}

fn makeFlagsAndAntiFlags(comptime E: type, comptime flags: anytype) struct {
    flags: std.EnumSet(E),
    antiflags: std.EnumSet(E),
} {
    const yes = std.EnumSet(E).init(flags);

    var no: std.EnumSet(E) = .{};
    inline for (@typeInfo(@TypeOf(flags)).Struct.fields) |f| {
        if (@field(flags, f.name) == false)
            no.insert(@field(E, f.name));
    }

    return .{ .flags = yes, .antiflags = no };
}

test "flags and antifalgs" {
    const Flags = enum { private, public, static, final };
    const input = .{ .public = true, .static = false };

    const ret = makeFlagsAndAntiFlags(Flags, input);
    const yes = ret.flags;
    const no = ret.antiflags;

    try std.testing.expect(yes.contains(.public));
    try std.testing.expect(!yes.contains(.static));
    try std.testing.expect(!yes.contains(.private));
    try std.testing.expect(!yes.contains(.final));

    try std.testing.expect(no.contains(.static));
    try std.testing.expect(!no.contains(.public));
    try std.testing.expect(!no.contains(.private));
    try std.testing.expect(!no.contains(.final));
}
