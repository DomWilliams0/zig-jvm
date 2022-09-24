const std = @import("std");
const io = std.io;
const log = std.log;
const Allocator = std.mem.Allocator;
const FieldDescriptor = @import("descriptor.zig").FieldDescriptor;
const MethodDescriptor = @import("descriptor.zig").MethodDescriptor;

pub const CafebabeError = error{
    BadMagic,
    BadFlags,
    UnsupportedVersion,
    MalformedConstantPool,
    BadConstantPoolIndex,
    InvalidDescriptor,
};

pub const ClassFile = struct {
    constant_pool: ConstantPool,
    flags: std.EnumSet(Flags),
    this_cls: []const u8,
    super_cls: ?[]const u8,
    interfaces: std.ArrayListUnmanaged([]const u8),
    fields: std.ArrayListUnmanaged(Field),
    methods: std.ArrayListUnmanaged(Method),
    /// Persistently allocated
    attributes: std.ArrayListUnmanaged(Attribute),

    pub const Flags = enum(u16) {
        public = 0x0001,
        final = 0x0010,
        super = 0x0020,
        interface = 0x0200,
        abstract = 0x0400,
        synthetic = 0x1000,
        annotation = 0x2000,
        enum_ = 0x4000,
        module = 0x8000,
    };

    /// Mostly allocated into the given arena, will be thrown away when class is linked EXCEPT
    /// * field, method and class attributes (arraylist and the contents of each attribute)
    pub fn load(arena: Allocator, persistent: Allocator, path: []const u8) !ClassFile {
        log.debug("loading class file {s}", .{path});

        var path_bytes: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path_abs = try std.fs.realpath(path, &path_bytes);

        var file = try std.fs.openFileAbsolute(path_abs, .{});
        const sz = try file.getEndPos();
        log.debug("file is {d} bytes", .{sz});
        const file_bytes = try arena.alloc(u8, sz);

        const n = try file.readAll(file_bytes);
        log.debug("read {d} bytes", .{n});

        const file_bytes_const: []const u8 = file_bytes;
        var stream = std.io.fixedBufferStream(file_bytes_const);
        return parse(arena, persistent, &stream);
    }

    pub fn deinit(self: @This(), persistent: Allocator) !void {
        const helper = struct {
            fn destroyAttributes(alloc: Allocator, attributes: *std.ArrayListUnmanaged(Attribute)) void {
                for (attributes.items) |x| {
                    var attr = x;
                    switch (attr) {
                        Attribute.code => |bytes| alloc.destroy(bytes.ptr),
                    }
                }

                attributes.deinit(alloc);
            }
        };

        for (self.fields.items) |x| {
            var field = x;
            helper.destroyAttributes(persistent, &field.attributes);
        }

        for (self.methods.items) |x| {
            var method = x;
            helper.destroyAttributes(persistent, &method.attributes);
        }

        var class = self;
        helper.destroyAttributes(persistent, &class.attributes);
    }

    fn parse(arena: Allocator, persistent: Allocator, buf: *std.io.FixedBufferStream([]const u8)) !ClassFile {
        // TODO could some of this be done with a packed struct? how does that work with unaligned ints.
        //  would need to convert from big to native endian anyway

        var reader = buf.reader();
        if (try reader.readIntBig(u32) != 0xcafebabe) return CafebabeError.BadMagic;

        var version = try readVersion(reader);
        log.debug("class version {d}.{d}", .{ version.major, version.minor });

        const is_supported = version.major >= 45 and version.major <= 62;
        if (!is_supported) {
            log.warn("classfile version {d}.{d} is unsupported", .{ version.major, version.minor });
            return CafebabeError.UnsupportedVersion;
        }

        const cp_len = try reader.readIntBig(u16);
        const constant_pool = try ConstantPool.parse(arena, buf, cp_len);

        const access_flags = try reader.readIntBig(u16);
        const flags = enumFromIntClass(ClassFile.Flags, access_flags) orelse return CafebabeError.BadFlags;

        const this_cls_idx = try reader.readIntBig(u16);
        const this_cls = constant_pool.lookupConstant(this_cls_idx) orelse return CafebabeError.BadConstantPoolIndex;
        const super_cls_idx = try reader.readIntBig(u16);
        const super_cls = constant_pool.lookupConstant(super_cls_idx) orelse return CafebabeError.BadConstantPoolIndex;

        var iface_count = try reader.readIntBig(u16);
        var ifaces = try std.ArrayListUnmanaged([]const u8).initCapacity(arena, iface_count);
        {
            while (iface_count > 0) {
                const idx = try reader.readIntBig(u16);
                const iface = constant_pool.lookupConstant(idx) orelse return CafebabeError.BadConstantPoolIndex;
                ifaces.appendAssumeCapacity(iface);
                iface_count -= 1;
            }
        }

        const fields = try parseFieldsOrMethods(Field, arena, persistent, &constant_pool, &reader);
        const methods = try parseFieldsOrMethods(Method, arena, persistent, &constant_pool, &reader);
        const attributes = try parseAttributes(persistent, &constant_pool, &reader);

        return ClassFile{ .constant_pool = constant_pool, .flags = flags, .this_cls = this_cls, .super_cls = super_cls, .interfaces = ifaces, .fields = fields, .methods = methods, .attributes = attributes };
    }

    // TODO errdefer release list
    fn parseAttributes(persistent: Allocator, cp: *const ConstantPool, reader: *Reader) !std.ArrayListUnmanaged(Attribute) {
        var attr_count = try reader.readIntBig(u16);
        var attrs = try std.ArrayListUnmanaged(Attribute).initCapacity(persistent, attr_count);
        while (attr_count > 0) {
            const attr_name_idx = try reader.readIntBig(u16);
            const attr_name = cp.lookupUtf8(attr_name_idx) orelse return CafebabeError.BadConstantPoolIndex;

            const attr_len = try reader.readIntBig(u32);

            // TODO perfect hash
            // TODO comptime check of allowed values for field/method/class
            if (std.mem.eql(u8, attr_name, "Code")) {
                const bytes_dst = try persistent.alloc(u8, attr_len);
                const n = try reader.read(bytes_dst);
                std.debug.assert(n == attr_len);
                attrs.appendAssumeCapacity(Attribute{ .code = bytes_dst });
            } else {
                try reader.skipBytes(attr_len, .{});
            }

            attr_count -= 1;
        }

        return attrs;
    }

    fn parseFieldsOrMethods(comptime T: type, arena: Allocator, persistent: Allocator, cp: *const ConstantPool, reader: *Reader) !std.ArrayListUnmanaged(T) {
        var count = try reader.readIntBig(u16);
        var list = try std.ArrayListUnmanaged(T).initCapacity(arena, count);

        while (count > 0) {
            const access_flags = try reader.readIntBig(u16);
            const flags = T.enumFromInt(T.Flags, access_flags) orelse return CafebabeError.BadFlags;
            const name_idx = try reader.readIntBig(u16);
            const desc_idx = try reader.readIntBig(u16);

            const name = cp.lookupUtf8(name_idx) orelse return CafebabeError.BadConstantPoolIndex;
            const desc_str = cp.lookupUtf8(desc_idx) orelse return CafebabeError.BadConstantPoolIndex;

            // validate desc
            const desc = T.descriptor.new(desc_str) orelse {
                std.log.warn("invalid descriptor '{s}'", .{desc_str});
                return CafebabeError.InvalidDescriptor;
            };
            // log.debug("field/method {s} {s}", .{ name, desc });

            const attributes = try parseAttributes(persistent, cp, reader);
            list.appendAssumeCapacity(.{ .flags = flags, .name = name, .descriptor = desc, .attributes = attributes });

            count -= 1;
        }

        return list;
    }
};

const Version = struct {
    major: u16,
    minor: u16,
};

const ClassAccessibility = enum(u16) {
    /// Declared public; may be accessed from outside its package.
    public = 0x0001,
    /// Declared final; no subclasses allowed.
    final = 0x0010,
    /// Treat superclass methods specially when invoked by the invokespecial instruction.
    super = 0x0020,
    /// Is an interface, not a class.
    interface = 0x0200,
    /// Declared abstract; must not be instantiated.
    abstract = 0x0400,
    /// Declared synthetic; not present in the source code.
    synthetic = 0x1000,
    /// Declared as an annotation type.
    annotation = 0x2000,
    /// Declared as an enum type.
    enum_ = 0x4000,
    /// Is a module, not a class or interface.
    module = 0x8000,
};

pub const Field = struct {
    flags: std.EnumSet(Flags),
    name: []const u8, // TODO decide where this lives, who owns it, how to share/intern
    descriptor: FieldDescriptor,
    /// This list and its elems are NOT allocated in arena, rather in a persistent
    /// allocator that JVM will keep around
    attributes: std.ArrayListUnmanaged(Attribute),
    // TODO ^ store slice instead, or just specifically the attrs needed like ConstantValue

    /// Offset of this field, calculated after cafebabe load.
    /// For static vars, offset into class storage, otherwise offset into object storage
    layout_offset: u16 = undefined,

    const descriptor = FieldDescriptor;

    pub const Flags = enum(u16) {
        public = 0x0001,
        private = 0x0002,
        protected = 0x0004,
        static = 0x0008,
        final = 0x0010,
        volatile_ = 0x0040,
        transient = 0x0080,
        synthetic = 0x1000,
        enum_ = 0x4000,
    };

    const enumFromInt = enumFromIntField; // temporary
};

pub const Method = struct {
    flags: std.EnumSet(Flags),
    name: []const u8,
    descriptor: MethodDescriptor,
    /// This list and its elems are NOT allocated in arena, rather in a persistent
    /// allocator that JVM will keep around
    attributes: std.ArrayListUnmanaged(Attribute),
    // TODO ^ store slice instead, or just specifically the attrs needed like Code

    const descriptor = MethodDescriptor;

    const Flags = enum(u16) {
        public = 0x0001,
        private = 0x0002,
        protected = 0x0004,
        static = 0x0008,
        final = 0x0010,
        synchronized = 0x0020,
        bridge = 0x0040,
        varargs = 0x0080,
        native = 0x0100,
        abstract = 0x0400,
        strict = 0x0800,
        synthetic = 0x1000,
    };
    const enumFromInt = enumFromIntMethod; // temporary
};

// TODO return type due to https://github.com/ziglang/zig/issues/12949 :(
fn enumFromIntField(comptime T: type, input: @typeInfo(T).Enum.tag_type) ?std.EnumSet(Field.Flags) {
    const all = comptime blk: {
        var bits = 0;
        inline for (@typeInfo(T).Enum.fields) |d| {
            bits |= d.value;
        }
        break :blk bits;
    };

    if ((input | all) != all) return null;

    var set: std.EnumSet(T) = undefined;
    set.bits.mask = @intCast(@TypeOf(set.bits.mask), input);
    return set;
}

// XXX see above
fn enumFromIntMethod(comptime T: type, input: @typeInfo(T).Enum.tag_type) ?std.EnumSet(Method.Flags) {
    const all = comptime blk: {
        var bits = 0;
        inline for (@typeInfo(T).Enum.fields) |d| {
            bits |= d.value;
        }
        break :blk bits;
    };

    if ((input | all) != all) return null;

    var set: std.EnumSet(T) = undefined;
    set.bits.mask = @intCast(@TypeOf(set.bits.mask), input);
    return set;
}

// XXX see above
fn enumFromIntClass(comptime T: type, input: @typeInfo(T).Enum.tag_type) ?std.EnumSet(ClassFile.Flags) {
    const all = comptime blk: {
        var bits = 0;
        inline for (@typeInfo(T).Enum.fields) |d| {
            bits |= d.value;
        }
        break :blk bits;
    };

    if ((input | all) != all) return null;

    var set: std.EnumSet(T) = undefined;
    set.bits.mask = @intCast(@TypeOf(set.bits.mask), input);
    return set;
}

pub const Attribute = union(enum) {
    code: []const u8,
};

const Reader = std.io.FixedBufferStream([]const u8).Reader;

fn readVersion(reader: Reader) !Version {
    const minor = try reader.readIntBig(u16);
    const major = try reader.readIntBig(u16);
    return Version{ .major = major, .minor = minor };
}

const ConstantPool = struct {
    const Self = @This();

    const Tag = enum(u8) {
        utf8 = 1,
        integer = 3,
        float = 4,
        long = 5,
        double = 6,
        class = 7,
        string = 8,
        fieldRef = 9,
        methodRef = 10,
        interfaceMethodRef = 11,
        nameAndType = 12,
        methodHandle = 15,
        methodType = 16,
        dynamic = 17,
        invokeDynamic = 18,
        module = 19,
        package = 20,
    };

    /// Allocated in the arena
    indices: []const (u16),
    slice: []const u8,

    fn parse(arena: Allocator, buf: *std.io.FixedBufferStream([]const u8), count: u16) !ConstantPool {
        var indices = try std.ArrayListUnmanaged(u16).initCapacity(arena, count + 1);
        _ = indices.addOneAssumeCapacity(); // idx 0 is never accessed

        const start_idx = buf.pos;

        var i: u16 = 1;
        const reader = buf.reader();
        while (i < count) {
            indices.appendAssumeCapacity(@intCast(u16, buf.pos - start_idx));

            const tag = reader.readEnum(Tag, std.builtin.Endian.Big) catch return CafebabeError.MalformedConstantPool;
            const len = switch (tag) {
                Tag.utf8 => try reader.readIntBig(u16),
                Tag.integer => 4,
                Tag.float => 4,
                Tag.long => 8,
                Tag.double => 8,
                Tag.class => 2,
                Tag.string => 2,
                Tag.fieldRef => 4,
                Tag.methodRef => 4,
                Tag.interfaceMethodRef => 4,
                Tag.nameAndType => 4,
                Tag.methodHandle => 3,
                Tag.methodType => 2,
                Tag.dynamic => 4,
                Tag.invokeDynamic => 4,
                Tag.module => 2,
                Tag.package => 2,
            };

            reader.skipBytes(len, .{ .buf_size = 64 }) catch unreachable;

            if (tag == Tag.long or tag == Tag.double) {
                indices.appendAssumeCapacity(65535); // invalid slot
                i += 2;
            } else {
                i += 1;
            }
        }

        const slice = buf.buffer[start_idx..buf.pos];
        // no need for toOwnedSlice, list is fully initialised and in arena
        return .{ .indices = indices.allocatedSlice(), .slice = slice };
    }

    pub fn lookupConstant(self: Self, idx_cp: u16) ?[]const u8 {
        const cls = self.lookup(idx_cp, Tag.class) orelse return null;

        const name_idx = std.mem.readInt(u16, &cls[0], std.builtin.Endian.Big);
        return self.lookupUtf8(name_idx);
    }

    pub fn lookupUtf8(self: Self, idx_cp: u16) ?[]const u8 {
        const name = self.lookup(idx_cp, Tag.utf8) orelse return null;

        const len = std.mem.readInt(u16, &name[0], std.builtin.Endian.Big);
        return name[2 .. 2 + len];
    }

    fn validateIndexCp(self: Self, idx_cp: u16) ?usize {
        // const idx = std.math.sub(u16, idx_cp, 1) catch return null; // adjust for 1 based indexing
        if (idx_cp == 0 or idx_cp >= self.indices.len + 1) {
            std.log.err("invalid constant pool index {d}", .{idx_cp});
            return null;
        }

        return self.indices[idx_cp];
    }

    /// Checks one-based index. Returns slice starting at body of element
    fn lookup(self: Self, index: u16, comptime tag: Tag) ?[]const u8 {
        const slice_idx = self.validateIndexCp(index) orelse return null;
        if (self.slice[slice_idx] != @enumToInt(tag)) {
            std.log.err("constant pool index {d} is a {d}, not expected {any}", .{ index, self.slice[slice_idx], tag });
            return null;
        } else {
            return self.slice[slice_idx + 1 ..];
        }
    }
};

test "parse class" {
    std.testing.log_level = .debug;

    const bytes = @embedFile("Test.class");
    const alloc = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var buf = std.io.fixedBufferStream(bytes);
    const classfile = ClassFile.parse(arena.allocator(), alloc, &buf) catch unreachable;

    try classfile.deinit(alloc);
}

test "parse flags" {
    try std.testing.expect(enumFromIntField(Field.Flags, 0) != null);
    try std.testing.expect(enumFromIntField(Field.Flags, 9999) == null);

    var valid = enumFromIntField(Field.Flags, 2 | 8 | 16) orelse unreachable;
    try std.testing.expect(valid.contains(.private));
    try std.testing.expect(valid.contains(.static));
    try std.testing.expect(valid.contains(.final));
    try std.testing.expect(!valid.contains(.public));
}
