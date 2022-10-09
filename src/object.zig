const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const vm_type = @import("type.zig");
const classloader = @import("classloader.zig");
const Allocator = std.mem.Allocator;
const Field = cafebabe.Field;
const Method = cafebabe.Method;

// TODO merge these with cafebabe class flags? merge at comptime possible?
pub const ClassStatus = packed struct {
    ty: enum(u2) { object, array, primitive },
};

/// Always allocated on GC heap
pub const VmClass = struct {
    constant_pool: cafebabe.ConstantPool,
    flags: std.EnumSet(cafebabe.ClassFile.Flags),
    name: []const u8, // constant pool reference
    super_cls: ?VmClassRef,
    interfaces: []VmClassRef,
    loader: classloader.WhichLoader,
    init_state: InitState = .uninitialised,
    monitor: Monitor = .{}, // TODO put into java.lang.Class object instance instead
    status: ClassStatus,

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

    pub fn formatVmRef(self: *const @This(), writer: anytype) !void {
        return std.fmt.format(writer, "{s}.class", .{self.name});
    }

    // ---------- field accessors
    fn findStaticField(self: @This(), name: []const u8, desc: []const u8) ?FieldId {
        return lookupFieldId(self.u.obj.fields, name, desc, .{ .static = true });
    }

    // TODO expose generic versions for each type instead
    pub fn getStaticField(self: *@This(), comptime T: type, field: FieldId) *T {
        switch (field) {
            .instance_offset => {
                @panic("not a static field ID");
            },
            .static_index => |idx| {
                const ptr = &self.u.obj.fields[idx].u.value;
                return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
            },
        }
    }

    /// Looks in superclasses and interfaces (5.4.3.3. Method Resolution).
    /// Does NOT check if class is not an interface, the caller should do this if needed
    pub fn findMethodRecursive(self: @This(), name: []const u8, desc: []const u8) ?*const Method {

        // TODO if signature polymorphic, resolve class names mentioned in descriptor too

        // check self and supers recursively first
        if (self.findMethodInSelfOrSupers(name, desc)) |m| return m;

        // check superinterfaces
        @panic("TODO find method in super interfaces");
    }

    /// Checks self and super classes only
    pub fn findMethodInSelfOrSupers(
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

    /// For invokevirtual and invokeinterface (5.4.6).
    /// Returned class ref is borrowed
    pub const SelectedMethod = struct { method: *const cafebabe.Method, cls: VmClassRef.Nullable };
    pub fn selectMethod(self: VmClassRef, resolved_method: *const cafebabe.Method) SelectedMethod {
        if (!resolved_method.flags.contains(.private)) {
            const helper = struct {
                /// 5.4.5
                fn canMethodOverride(overriding_method: *const cafebabe.Method, override_candidate: *const cafebabe.Method) bool {
                    const m_c = overriding_method;
                    const m_a = override_candidate;
                    return (std.mem.eql(u8, m_c.name, m_a.name) and
                        std.mem.eql(u8, m_c.descriptor.str, m_a.descriptor.str) and
                        (m_a.flags.contains(.public) or
                        m_a.flags.contains(.protected))); // TODO complicated transitive runtime package comparisons oh god
                    // compiler segfaults on `or @panic(...)`, issue Z
                }

                /// Returns borrowed class ref
                fn checkSuperClasses(cls_ref: VmClassRef, method: *const cafebabe.Method) ?SelectedMethod {
                    const cls = cls_ref.get();
                    // check own methods
                    for (cls.u.obj.methods) |m, i| {
                        if (canMethodOverride(&m, method)) return .{ .method = &cls.u.obj.methods[i], .cls = cls_ref.intoNullable() };
                    }

                    // recurse on super class
                    if (cls.super_cls) |super| if (checkSuperClasses(super, method)) |m| return m;

                    return null;
                }
            };

            // check super classes recursively
            if (helper.checkSuperClasses(self, resolved_method)) |m| return m;

            // TODO check super interfaces

        }

        return .{ .method = resolved_method, .cls = VmClassRef.Nullable.nullRef() };
    }

    /// Looks in self, superinterfaces then superclasses (5.4.3.2)
    pub fn findFieldInSupers(
        self: @This(),
        name: []const u8,
        desc: []const u8,
        flags: anytype,
    ) ?*const Field {
        // check self first
        if (self.findFieldInThisOnly(name, desc, flags)) |f| return f;

        // check superinterfaces recursively
        for (self.interfaces) |iface| if (iface.get().findFieldInSupers(name, desc, flags)) |f| return f;

        // check super class
        if (self.super_cls) |super| if (super.get().findFieldInSupers(name, desc, flags)) |f| return f;

        return null;
    }

    /// Looks in self only
    fn findFieldInThisOnly(
        self: @This(),
        name: []const u8,
        desc: []const u8,
        flags: anytype,
    ) ?*const Field {
        const pls = makeFlagsAndAntiFlags(Field.Flags, flags);
        return for (self.u.obj.fields) |m, i| {
            if ((m.flags.bits.mask & pls.flags.bits.mask) == pls.flags.bits.mask and
                (m.flags.bits.mask & ~(pls.antiflags.bits.mask)) == m.flags.bits.mask and
                std.mem.eql(u8, desc, m.descriptor.str) and std.mem.eql(u8, name, m.name))
            {
                break &self.u.obj.fields[i];
            }
        } else null;
    }

    pub fn isObject(self: @This()) bool {
        return self.status.ty == .object;
    }
    pub fn isPrimitive(self: @This()) bool {
        return self.status.ty == .primitive;
    }
    pub fn isArray(self: @This()) bool {
        return self.status.ty == .array;
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

    /// Self is cloned to pass to object
    pub fn instantiateObject(self: VmClassRef) VmObjectRef {
        const cls = self.get();
        std.log.debug("instantiating object of class {s}", .{cls.name});

        // allocate
        const layout = cls.u.obj.layout;
        var obj_ref = VmObjectRef.new_uninit(layout.instance_offset, null) catch @panic("out of memory");
        obj_ref.get().* = VmObject{
            .class = self.clone(),
            .storage = {},
        };

        // set default field values, luckily all zero bits is +0.0 for floats+doubles, and null ptrs (TODO really for objects?)
        var field_bytes = @ptrCast([*]u8, @alignCast(1, &obj_ref.get().storage));
        std.mem.set(u8, field_bytes[0..layout.instance_offset], 0);

        return obj_ref;
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
    class: VmClassRef,
    /// Where variable data storage begins
    storage: void,

    // ---------- VmRef interface
    pub fn vmRefSize(self: *const VmObject) usize {
        const cls = self.class.get();
        return if (cls.isObject())
            cls.u.obj.layout.instance_offset
        else if (cls.isArray()) @panic("TODO array instantiation") else 0;
    }
    pub fn vmRefDrop(self: *@This()) void {
        self.class.drop();
    }

    pub fn formatVmRef(self: *const @This(), writer: anytype) !void {
        return std.fmt.format(writer, "{s}", .{self.class.get().name});
    }

    /// Instance field
    pub fn getField(self: *@This(), comptime T: type, field: FieldId) *T {
        switch (field) {
            .instance_offset => |offset| {
                var byte_ptr: [*]u8 = @ptrCast([*]u8, self);
                return @ptrCast(*T, @alignCast(@alignOf(T), byte_ptr + offset));
            },
            .static_index => {
                @panic("not an instance field ID");
            },
        }
    }

    fn findInstanceField(self: @This(), name: []const u8, desc: []const u8) ?FieldId {
        return lookupFieldId(self.class.get().u.obj.fields, name, desc, .{ .static = false });
    }

    /// Instance field
    pub fn getFieldFromField(self: *@This(), comptime T: type, field: *const cafebabe.Field) *T {
        const offset = field.u.layout_offset;
        var byte_ptr: [*]u8 = @ptrCast([*]u8, self);
        return @ptrCast(*T, @alignCast(@alignOf(T), byte_ptr + offset));
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
    /// Exact offset from start of object to end of field storage
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

        fn checkFieldValue(comptime T: type, obj: VmObjectRef, name: []const u8, desc: []const u8, val: T) !void {
            return std.testing.expectEqual(val, obj.get().getField(T, obj.get().findInstanceField(name, desc) orelse unreachable).*);
        }

        fn setFieldValue(value: anytype, obj: VmObjectRef, name: []const u8, desc: []const u8) void {
            const f = obj.get().getField(@TypeOf(value), obj.get().findInstanceField(name, desc) orelse unreachable);
            f.* = value;
        }
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

    const static_int_val = cls.get().getStaticField(i32, cls.get().findStaticField("myIntStatic", "I") orelse unreachable);
    static_int_val.* = 0x12345678;
}

test "allocate object" {
    // std.testing.log_level = .debug;
    const helper = test_helper();
    var alloc = std.testing.allocator;

    var layout = ObjectLayout{};
    try defineObjectLayout(alloc, &helper.fields, &layout);

    // init global allocator
    const handle = try @import("jvm.zig").ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    // allocate class with static storage
    const cls = try vm_alloc.allocClass();
    cls.get().name = "Dummy";
    cls.get().u = .{ .obj = .{ .fields = &helper.fields, .layout = layout, .methods = undefined } }; // only instance fields
    defer cls.drop();

    // allocate object
    const obj = VmClass.instantiateObject(cls);
    defer obj.drop();

    // check default field values
    try helper.checkFieldValue(i64, obj, "myLong", "J", 0);
    try helper.checkFieldValue(f64, obj, "myDouble", "D", 0.0);
    try helper.checkFieldValue(i32, obj, "myInt", "I", 0);
    try helper.checkFieldValue(i32, obj, "myInt2", "I", 0);
    try helper.checkFieldValue(bool, obj, "myBool", "Z", false);

    // set values and ensure no overlap
    helper.setFieldValue(@as(i64, 1234_5678_1234), obj, "myLong", "J");

    try helper.checkFieldValue(i64, obj, "myLong", "J", 1234_5678_1234);
    try helper.checkFieldValue(f64, obj, "myDouble", "D", 0.0);
    try helper.checkFieldValue(i32, obj, "myInt", "I", 0);
    try helper.checkFieldValue(i32, obj, "myInt2", "I", 0);
    try helper.checkFieldValue(bool, obj, "myBool", "Z", false);

    helper.setFieldValue(@as(f64, -123.45), obj, "myDouble", "D");

    try helper.checkFieldValue(i64, obj, "myLong", "J", 1234_5678_1234);
    try helper.checkFieldValue(f64, obj, "myDouble", "D", -123.45);
    try helper.checkFieldValue(i32, obj, "myInt", "I", 0);
    try helper.checkFieldValue(i32, obj, "myInt2", "I", 0);
    try helper.checkFieldValue(bool, obj, "myBool", "Z", false);

    helper.setFieldValue(true, obj, "myBool", "Z"); // change the order a bit

    try helper.checkFieldValue(i64, obj, "myLong", "J", 1234_5678_1234);
    try helper.checkFieldValue(f64, obj, "myDouble", "D", -123.45);
    try helper.checkFieldValue(i32, obj, "myInt", "I", 0);
    try helper.checkFieldValue(i32, obj, "myInt2", "I", 0);
    try helper.checkFieldValue(bool, obj, "myBool", "Z", true);

    helper.setFieldValue(@as(i32, 123456), obj, "myInt", "I");

    try helper.checkFieldValue(i64, obj, "myLong", "J", 1234_5678_1234);
    try helper.checkFieldValue(f64, obj, "myDouble", "D", -123.45);
    try helper.checkFieldValue(i32, obj, "myInt", "I", 123456);
    try helper.checkFieldValue(i32, obj, "myInt2", "I", 0);
    try helper.checkFieldValue(bool, obj, "myBool", "Z", true);

    helper.setFieldValue(@as(i32, 789012), obj, "myInt2", "I");

    try helper.checkFieldValue(i64, obj, "myLong", "J", 1234_5678_1234);
    try helper.checkFieldValue(f64, obj, "myDouble", "D", -123.45);
    try helper.checkFieldValue(i32, obj, "myInt", "I", 123456);
    try helper.checkFieldValue(i32, obj, "myInt2", "I", 789012);
    try helper.checkFieldValue(bool, obj, "myBool", "Z", true);
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

test "flags and antiflags" {
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
