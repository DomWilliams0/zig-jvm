const std = @import("std");
const jni = @import("jni.zig");
const native = @import("native.zig");
const io = std.io;
const log = std.log;
const Allocator = std.mem.Allocator;
const FieldDescriptor = @import("descriptor.zig").FieldDescriptor;
const MethodDescriptor = @import("descriptor.zig").MethodDescriptor;

// constant pool should be persistent but stay the same. when resolving things, change insn to lookup from a separate runtime area

pub const CafebabeError = error{
    BadMagic,
    BadFlags,
    UnsupportedVersion,
    MalformedConstantPool,
    BadConstantPoolIndex,
    InvalidDescriptor,
    DuplicateAttribute,
    UnexpectedCodeOrLackThereof,
};

/// Mostly allocated persistently with everything moved out of this instance into a runtime type
pub const ClassFile = struct {
    constant_pool: ConstantPool,
    flags: BitSet(Flags),
    this_cls: []const u8, // constant pool
    super_cls: ?[]const u8, // constant pool
    interfaces: std.ArrayListUnmanaged([]const u8), // point into constant pool
    fields: []Field,
    methods: []Method,

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

    /// Path can be relative. See `load`
    pub fn loadFile(arena: *std.heap.ArenaAllocator, persistent: Allocator, path: []const u8) !ClassFile {
        var path_bytes: [std.fs.MAX_PATH_BYTES]u8 = undefined; // TODO stat to check exists, then put this in arena to avoid filling the stack
        const path_abs = try std.fs.realpath(path, &path_bytes);
        // TODO expand path too e.g. ~

        var file = try std.fs.openFileAbsolute(path_abs, .{});
        const sz = try file.getEndPos();

        log.debug("loading class file {s} ({d} bytes)", .{ path, sz });
        const file_bytes = try arena.alloc(u8, sz);

        const n = try file.readAll(file_bytes);
        log.debug("read {d} bytes", .{n});

        const file_bytes_const: []const u8 = file_bytes;
        var stream = std.io.fixedBufferStream(file_bytes_const);
        return parse(arena, persistent, &stream);
    }

    pub fn parse(arena: Allocator, persistent: Allocator, buf: *std.io.FixedBufferStream([]const u8)) !ClassFile {
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
        var constant_pool = try ConstantPool.parse(persistent, buf, cp_len);
        errdefer constant_pool.deinit(persistent);

        const access_flags = try reader.readIntBig(u16);
        const flags = enumFromIntClass(ClassFile.Flags, access_flags) orelse return CafebabeError.BadFlags;

        const this_cls_idx = try reader.readIntBig(u16);
        const this_cls = constant_pool.lookupClass(this_cls_idx) orelse return CafebabeError.BadConstantPoolIndex;
        const super_cls_idx = try reader.readIntBig(u16);
        const super_cls = if (super_cls_idx == 0 and std.mem.eql(u8, this_cls, "java/lang/Object")) null else constant_pool.lookupClass(super_cls_idx) orelse return CafebabeError.BadConstantPoolIndex;

        var iface_count = try reader.readIntBig(u16);
        var ifaces = try std.ArrayListUnmanaged([]const u8).initCapacity(persistent, iface_count);
        {
            while (iface_count > 0) {
                const idx = try reader.readIntBig(u16);
                const iface = constant_pool.lookupClass(idx) orelse return CafebabeError.BadConstantPoolIndex;
                ifaces.appendAssumeCapacity(iface);
                iface_count -= 1;
            }
        }

        const fields = try parseFieldsOrMethods(Field, arena, persistent, this_cls, &constant_pool, &reader, buf);
        const methods = try parseFieldsOrMethods(Method, arena, persistent, this_cls, &constant_pool, &reader, buf);
        const attributes = try parseAttributes(arena, &constant_pool, &reader, buf);
        _ = attributes; // TODO use class attributes
        return ClassFile{
            .constant_pool = constant_pool,
            .flags = flags,
            .this_cls = this_cls,
            .super_cls = super_cls,
            .interfaces = ifaces,
            .fields = fields,
            .methods = methods,
        };
    }
    // TODO errdefer release list

    /// Collects into arena map of name->bytes
    // TODO dont do this, pass the name+reader to T who can read it into persistent
    // alloc or just skip it
    fn parseAttributes(arena: Allocator, cp: *const ConstantPool, reader: *Reader, buf: *std.io.FixedBufferStream([]const u8)) !std.StringHashMapUnmanaged([]const u8) {
        var attr_count = try reader.readIntBig(u16);
        var attrs: std.StringHashMapUnmanaged([]const u8) = .{};
        try attrs.ensureTotalCapacity(arena, attr_count);
        while (attr_count > 0) {
            const attr_name_idx = try reader.readIntBig(u16);
            const attr_name = cp.lookupUtf8(attr_name_idx) orelse return CafebabeError.BadConstantPoolIndex;

            const attr_len = try reader.readIntBig(u32);
            const body_start = buf.pos;
            try reader.skipBytes(attr_len, .{});
            const attr_bytes = buf.buffer[body_start..buf.pos];

            const existing = attrs.fetchPutAssumeCapacity(attr_name, attr_bytes);
            if (existing) |kv| {
                std.log.warn("duplicate attribute {s}", .{kv.key});
                return error.DuplicateAttribute;
            }

            attr_count -= 1;
        }

        return attrs;
    }

    /// Arena is just for temporary attribute storage (TODO redo this)
    fn parseFieldsOrMethods(comptime T: type, arena: Allocator, persistent: Allocator, class_name: []const u8, cp: *const ConstantPool, reader: *Reader, buf: *std.io.FixedBufferStream([]const u8)) ![]T {
        const count = try reader.readIntBig(u16);
        var slice = try persistent.alloc(T, count);
        errdefer persistent.free(slice);
        var cursor: usize = 0;

        while (cursor < count) {
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
            // log.debug("field/method {s} {s}", .{ name, desc.str });

            const attributes = try parseAttributes(arena, cp, reader, buf);
            const instance = try T.new(persistent, arena, class_name, cp, flags, name, desc, attributes);
            slice[cursor] = instance;
            cursor += 1;
        }

        return slice;
    }

    /// Only call on error, throws away persistently allocated things needed at runtime
    pub fn deinit(self: *@This(), persistent: Allocator) void {
        for (self.methods) |method| {
            method.deinit(persistent);
        }

        persistent.free(self.methods);
        persistent.free(self.fields);
        self.interfaces.deinit(persistent);
        self.constant_pool.deinit(persistent);
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
    flags: BitSet(Flags),
    name: []const u8, // points into constant pool
    descriptor: FieldDescriptor,
    // TODO attributes

    u: union {
        /// Non static: offset of this field in object storage, calculated after cafebabe load
        layout_offset: u16,
        /// Static: the value
        value: u64,
    } = undefined,

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

    fn new(persistent: Allocator, _: Allocator, _: []const u8, _: *const ConstantPool, flags: BitSet(Flags), name: []const u8, desc: FieldDescriptor, attributes: std.StringHashMapUnmanaged([]const u8)) !@This() {
        _ = attributes;
        _ = persistent;

        // TODO consume needed field attributes
        return Field{ .name = name, .descriptor = desc, .flags = flags };
    }
};

pub const Method = struct {
    flags: BitSet(Flags),
    name: []const u8, // points into constant pool
    class_name: []const u8, // constant pool
    descriptor: MethodDescriptor,
    code: Code,

    const descriptor = MethodDescriptor;

    pub const Flags = enum(u16) {
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

    pub const ExceptionHandler = struct {
        start_pc: u16,
        end_pc: u16,
        handler_pc: u16,
        /// Name of class to catch, null for `finally` block
        catch_type: ?[]const u8,
    };

    pub const Code = union(enum) {
        java: struct {
            max_stack: u16,
            max_locals: u16,
            /// null if abstract
            code: ?[]const u8,
            exception_handlers: []ExceptionHandler,
        },

        native: native.NativeCode,

        pub fn deinit(self: @This(), alloc: Allocator) void {
            if (self == .java) {
                if (self.java.code) |c| alloc.free(c);
                alloc.free(self.java.exception_handlers);
            }
        }
    };

    fn new(persistent: Allocator, arena: Allocator, class_name: []const u8, cp: *const ConstantPool, flags: BitSet(Flags), name: []const u8, desc: MethodDescriptor, attributes: std.StringHashMapUnmanaged([]const u8)) !@This() {
        var code = Code{
            .java = .{
                .max_stack = 0,
                .max_locals = 0,
                .code = null,
                .exception_handlers = &.{}, // should be safe to alloc.free
            },
        };
        if (attributes.get("Code")) |attr| {
            var buf = std.io.fixedBufferStream(attr);
            var reader = buf.reader();

            code.java.max_stack = try reader.readIntBig(u16);
            code.java.max_locals = try reader.readIntBig(u16);
            const code_len = try reader.readIntBig(u32);
            // align code to 4 bytes so tableswitch and lookupswitch are aligned too (4.7.3)
            const code_buf = try persistent.allocWithOptions(u8, code_len, 4, null);
            errdefer persistent.free(code_buf);

            const n = try reader.read(code_buf);
            if (n != code_len) return error.MalformedConstantPool;

            var exc_len = try reader.readIntBig(u16);
            const exc_table = try persistent.alloc(ExceptionHandler, exc_len);
            errdefer persistent.free(exc_table);
            while (exc_len > 0) : (exc_len -= 1) {
                exc_table[exc_table.len - exc_len] = ExceptionHandler{
                    .start_pc = try reader.readIntBig(u16),
                    .end_pc = try reader.readIntBig(u16),
                    .handler_pc = try reader.readIntBig(u16),
                    .catch_type = blk: {
                        const idx = try reader.readIntBig(u16);
                        break :blk if (idx == 0) null else cp.lookupClass(idx) orelse return error.BadConstantPoolIndex;
                    },
                };
            }

            const code_attributes = try ClassFile.parseAttributes(arena, cp, &reader, &buf);
            _ = code_attributes; // TODO use code attributes

            code.java.code = code_buf;
            code.java.exception_handlers = exc_table;
        }
        errdefer code.deinit(persistent);

        const has_code = code.java.code != null;
        const should_have_code = !(flags.contains(.abstract) or flags.contains(.native));
        if (has_code != should_have_code) {
            log.warn("method {s} code mismatch, has={any}, should_have={any}", .{ name, has_code, should_have_code });
            return error.UnexpectedCodeOrLackThereof;
        }

        if (flags.contains(.native)) {
            code = .{ .native = native.NativeCode.new() };
        }

        return Method{ .name = name, .descriptor = desc, .flags = flags, .code = code, .class_name = class_name };
    }

    pub fn deinit(self: @This(), persistent: Allocator) void {
        self.code.deinit(persistent);
    }
};

// TODO return type due to https://github.com/ziglang/zig/issues/12949 :(
fn enumFromIntField(comptime T: type, input: @typeInfo(T).Enum.tag_type) ?BitSet(Field.Flags) {
    const all = comptime blk: {
        var bits = 0;
        inline for (@typeInfo(T).Enum.fields) |d| {
            bits |= d.value;
        }
        break :blk bits;
    };

    if ((input | all) != all) return null;

    var set: BitSet(T) = undefined;
    set.bits = @truncate(u16, input);
    return set;
}

// XXX see above
fn enumFromIntMethod(comptime T: type, input: @typeInfo(T).Enum.tag_type) ?BitSet(Method.Flags) {
    const all = comptime blk: {
        var bits = 0;
        inline for (@typeInfo(T).Enum.fields) |d| {
            bits |= d.value;
        }
        break :blk bits;
    };

    if ((input | all) != all) return null;

    var set: BitSet(T) = undefined;
    set.bits = @truncate(u16, input);
    return set;
}

// XXX see above
fn enumFromIntClass(comptime T: type, input: @typeInfo(T).Enum.tag_type) ?BitSet(ClassFile.Flags) {
    const all = comptime blk: {
        var bits = 0;
        inline for (@typeInfo(T).Enum.fields) |d| {
            bits |= d.value;
        }
        break :blk bits;
    };

    if ((input | all) != all) return null;

    var set: BitSet(T) = undefined;
    set.bits = @truncate(u16, input);
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

pub const ConstantPool = struct {
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

    indices: []u16,
    /// Persistent copy from classfile
    slice: []const u8,

    fn parse(alloc: Allocator, buf: *std.io.FixedBufferStream([]const u8), count: u16) !ConstantPool {
        var indices = try alloc.alloc(u16, count + 1);
        errdefer alloc.free(indices);
        var next_idx: usize = 1; // idx 0 is never accessed

        const start_idx = buf.pos;

        var i: u16 = 1;
        const reader = buf.reader();
        while (i < count) {
            indices[next_idx] = @intCast(u16, buf.pos - start_idx);
            next_idx += 1;

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

            try reader.skipBytes(len, .{ .buf_size = 64 });

            if (tag == Tag.long or tag == Tag.double) {
                indices[next_idx] = 65535; // invalid slot
                next_idx += 1;
                i += 2;
            } else {
                i += 1;
            }
        }

        // copy from arena into persistent
        var copy_buf = try alloc.dupe(u8, buf.buffer[start_idx..buf.pos]);
        return .{ .indices = indices, .slice = copy_buf };
    }

    // TODO infallible versions of these functions (or comptime magic) for fast runtime lookups. maybe a view abstraction over a constantpool.
    //   return an error but in infallible declare errorset as error{}, should be optimised out
    // TODO special case of `this` class reference, already resolved

    pub fn lookupClass(self: Self, idx_cp: u16) ?[]const u8 {
        const cls = self.lookup(idx_cp, Tag.class) orelse return null;

        const name_idx = std.mem.readInt(u16, &cls[0], std.builtin.Endian.Big);
        return self.lookupUtf8(name_idx);
    }

    pub fn lookupMethod(self: Self, idx_cp: u16) ?struct { name: []const u8, ty: []const u8, cls: []const u8 } {
        const body = self.lookup(idx_cp, Tag.methodRef) orelse return null;
        const cls_idx = std.mem.readInt(u16, &body[0], std.builtin.Endian.Big);
        const name_and_type_idx = std.mem.readInt(u16, &body[2], std.builtin.Endian.Big);

        const cls = self.lookupClass(cls_idx) orelse return null;
        const name_and_type = self.lookupNameAndType(name_and_type_idx) orelse return null;
        return .{ .name = name_and_type.name, .ty = name_and_type.ty, .cls = cls };
    }

    pub fn lookupMethodOrInterfaceMethod(self: Self, idx_cp: u16) ?struct { name: []const u8, ty: []const u8, cls: []const u8, is_interface: bool } {
        const method = self.lookupMany(idx_cp, .{ Tag.methodRef, Tag.interfaceMethodRef }) orelse return null;
        const cls_idx = std.mem.readInt(u16, &method.body[0], std.builtin.Endian.Big);
        const name_and_type_idx = std.mem.readInt(u16, &method.body[2], std.builtin.Endian.Big);

        const cls = self.lookupClass(cls_idx) orelse return null;
        const name_and_type = self.lookupNameAndType(name_and_type_idx) orelse return null;
        return .{ .name = name_and_type.name, .ty = name_and_type.ty, .cls = cls, .is_interface = method.tag == Tag.interfaceMethodRef };
    }

    pub fn lookupField(self: Self, idx_cp: u16) ?struct { name: []const u8, ty: []const u8, cls: []const u8 } {
        const body = self.lookup(idx_cp, Tag.fieldRef) orelse return null;
        const cls_idx = std.mem.readInt(u16, &body[0], std.builtin.Endian.Big);
        const name_and_type_idx = std.mem.readInt(u16, &body[2], std.builtin.Endian.Big);

        const cls = self.lookupClass(cls_idx) orelse return null;
        const name_and_type = self.lookupNameAndType(name_and_type_idx) orelse return null;
        return .{ .name = name_and_type.name, .ty = name_and_type.ty, .cls = cls };
    }

    fn lookupNameAndType(self: Self, idx_cp: u16) ?struct { name: []const u8, ty: []const u8 } {
        const body = self.lookup(idx_cp, Tag.nameAndType) orelse return null;
        const name_idx = std.mem.readInt(u16, &body[0], std.builtin.Endian.Big);
        const ty_idx = std.mem.readInt(u16, &body[2], std.builtin.Endian.Big);

        return .{
            .name = self.lookupUtf8(name_idx) orelse return null,
            .ty = self.lookupUtf8(ty_idx) orelse return null,
        };
    }

    pub fn lookupUtf8(self: Self, idx_cp: u16) ?[]const u8 {
        const name = self.lookup(idx_cp, Tag.utf8) orelse return null;

        const len = std.mem.readInt(u16, &name[0], std.builtin.Endian.Big);
        return name[2 .. 2 + len];
    }

    pub const LoadableConstant = union(enum) {
        /// Class name
        class: []const u8,
        long: i64,
        double: f64,
        string: []const u8,
    };

    pub const ConstantLookupOption = enum {
        any_single,
        any_wide,
        long_double,
    };
    pub fn lookupConstant(self: Self, idx_cp: u16, comptime opt: ConstantLookupOption) ?LoadableConstant {
        const tags = switch (opt) {
            .any_single => .{
                Tag.integer,
                Tag.float,
                Tag.class,
                Tag.string,
                Tag.methodHandle,
                Tag.methodType,
                Tag.dynamic,
            },
            .any_wide => .{ Tag.integer, Tag.float, Tag.class, Tag.string, Tag.methodHandle, Tag.methodType, Tag.dynamic, Tag.long, Tag.double },
            .long_double => .{ Tag.long, Tag.double },
        };
        const constant = self.lookupMany(idx_cp, tags) orelse return null;
        return switch (constant.tag) {
            .class => .{ .class = self.lookupUtf8(std.mem.readIntBig(u16, &constant.body[0])) orelse return null },
            .long => .{ .long = @bitCast(i64, (@as(u64, std.mem.readIntBig(u32, &constant.body[0])) << 32) + std.mem.readIntBig(u32, &constant.body[4])) },
            .double => .{ .double = @bitCast(f64, (@as(u64, std.mem.readIntBig(u32, &constant.body[0])) << 32) + std.mem.readIntBig(u32, &constant.body[4])) },
            .string => .{ .string = self.lookupUtf8(std.mem.readIntBig(u16, &constant.body[0])) orelse return null },
            else => std.debug.panic("TODO other constants: {s}", .{@tagName(constant.tag)}),
        };
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
    fn lookupMany(self: Self, index: u16, comptime tags: anytype) ?struct { body: []const u8, tag: Tag } {
        const slice_idx = self.validateIndexCp(index) orelse return null;
        inline for (@typeInfo(@TypeOf(tags)).Struct.fields) |decl| {
            const enum_value = @ptrCast(*const Tag, decl.default_value.?).*;

            if (self.slice[slice_idx] == @enumToInt(enum_value))
                return .{ .body = self.slice[slice_idx + 1 ..], .tag = enum_value };
        }

        std.log.err("constant pool index {d} is a {d}, not one of expected {any}", .{ index, self.slice[slice_idx], tags });
        return null;
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

    pub fn deinit(self: *@This(), persistent: Allocator) void {
        persistent.free(self.indices);
        persistent.free(self.slice);
    }
};

test "parse class" {
    // std.testing.log_level = .debug;

    const bytes = @embedFile("Test.class");
    const alloc = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var buf = std.io.fixedBufferStream(bytes);
    var classfile = ClassFile.parse(arena.allocator(), alloc, &buf) catch unreachable;

    classfile.deinit(alloc);
}

test "no leaks on invalid class" {
    // std.testing.log_level = .debug;

    const bytes = @embedFile("Test.class")[0..200]; // truncated
    const alloc = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var buf = std.io.fixedBufferStream(bytes);
    _ = ClassFile.parse(arena.allocator(), alloc, &buf) catch {};
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

pub fn BitSet(comptime E: type) type {
    return struct {
        bits: u16,

        /// types = set of bits to set
        pub fn init(types: anytype) @This() {
            var bits: @This() = .{ .bits = 0 };
            inline for (@typeInfo(@TypeOf(types)).Struct.fields) |f| {
                bits.insert(@field(E, f.name));
            }

            return bits;
        }

        pub fn insert(self: *@This(), e: E) void {
            self.bits |= @enumToInt(e);
        }

        pub fn remove(self: *@This(), e: E) void {
            self.bits &= ~@enumToInt(e);
        }

        pub fn contains(self: @This(), e: E) bool {
            return (self.bits & @enumToInt(e)) != 0;
        }
    };
}

test "method flags" {
    std.testing.log_level = .debug;
    var flags = enumFromIntMethod(Method.Flags, @as(u16, 1025)) orelse unreachable;
    try std.testing.expect(flags.contains(.public));
    try std.testing.expect(flags.contains(.abstract));

    try std.testing.expect(!flags.contains(.native));
    flags.insert(.native);
    try std.testing.expect(flags.contains(.native));
    flags.remove(.native);
    try std.testing.expect(!flags.contains(.native));

    const inited = BitSet(Method.Flags).init(.{ .native = true, .public = true });
    try std.testing.expect(inited.contains(.native));
    try std.testing.expect(inited.contains(.public));
    try std.testing.expect(!inited.contains(.private));
}
