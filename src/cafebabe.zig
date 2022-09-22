const std = @import("std");
const root = @import("root");
const io = std.io;
const log = std.log;
const Allocator = std.mem.Allocator;

pub const CafebabeError = error{
    BadMagic,
    UnsupportedVersion,
    MalformedConstantPool,
    BadConstantPoolIndex,
};

pub const ClassFile = struct {
    constant_pool: ConstantPool,
    access_flags: u16,
    this_cls: []const u8,
    super_cls: ?[]const u8,
    interfaces: std.ArrayListUnmanaged([]const u8),
    fields: std.ArrayListUnmanaged(FieldOrMethod),
    methods: std.ArrayListUnmanaged(FieldOrMethod),
    /// Persistently allocated
    attributes: std.ArrayListUnmanaged(Attribute),

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

        const fields = try parseFieldsOrMethods(arena, persistent, &constant_pool, &reader);

        const methods = try parseFieldsOrMethods(arena, persistent, &constant_pool, &reader);

        const attributes = try parseAttributes(persistent, &constant_pool, &reader);

        return ClassFile{ .constant_pool = constant_pool, .access_flags = access_flags, .this_cls = this_cls, .super_cls = super_cls, .interfaces = ifaces, .fields = fields, .methods = methods, .attributes = attributes };
    }

    fn parseAttributes(persistent: Allocator, cp: *const ConstantPool, reader: *Reader) !std.ArrayListUnmanaged(Attribute) {
        var attr_count = try reader.readIntBig(u16);
        var attrs = try std.ArrayListUnmanaged(Attribute).initCapacity(persistent, attr_count);
        while (attr_count > 0) {
            const attr_name_idx = try reader.readIntBig(u16);
            const attr_name = cp.lookupUtf8(attr_name_idx) orelse return CafebabeError.BadConstantPoolIndex;
            log.debug("attribute {s}", .{attr_name});

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

    fn parseFieldsOrMethods(arena: Allocator, persistent: Allocator, cp: *const ConstantPool, reader: *Reader) !std.ArrayListUnmanaged(FieldOrMethod) {
        var count = try reader.readIntBig(u16);
        var list = try std.ArrayListUnmanaged(FieldOrMethod).initCapacity(arena, count);

        while (count > 0) {
            const access_flags = try reader.readIntBig(u16);
            const name_idx = try reader.readIntBig(u16);
            const desc_idx = try reader.readIntBig(u16);

            const name = cp.lookupUtf8(name_idx) orelse return CafebabeError.BadConstantPoolIndex;
            const desc = cp.lookupUtf8(desc_idx) orelse return CafebabeError.BadConstantPoolIndex;
            // log.debug("field/method {s} {s}", .{ name, desc });

            const attributes = try parseAttributes(persistent, cp, reader);
            list.appendAssumeCapacity(FieldOrMethod{ .access_flags = access_flags, .name = name, .descriptor = desc, .attributes = attributes });

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

/// Only access flags type differ
const FieldOrMethod = struct {
    access_flags: u16,
    name: []const u8,
    descriptor: []const u8,
    /// This list and its elems are NOT allocated in arena, rather in a persistent
    /// allocator that JVM will keep around
    attributes: std.ArrayListUnmanaged(Attribute),
};

const Attribute = union(enum) {
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
    indices: std.ArrayListUnmanaged(u16),
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
        return .{ .indices = indices, .slice = slice };
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
        if (idx_cp == 0 or idx_cp >= self.indices.items.len + 1) {
            std.log.err("invalid constant pool index {d}", .{idx_cp});
            return null;
        }

        return self.indices.items[idx_cp];
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

test "parse" {
    std.testing.log_level = .debug;

    const bytes = @embedFile("Test.class");
    const alloc = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var buf = std.io.fixedBufferStream(bytes);
    const classfile = ClassFile.parse(arena.allocator(), alloc, &buf) catch unreachable;

    try classfile.deinit(alloc);
}
