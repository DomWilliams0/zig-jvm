const std = @import("std");
const jvm = @import("jvm");
const state = @import("state.zig");
const cafebabe = @import("cafebabe.zig");
const vm_alloc = @import("alloc.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");
const descriptor = @import("descriptor.zig");
const native = @import("native.zig");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

const VmClassRef = object.VmClassRef;
const VmObjectRef = object.VmObjectRef;

pub const WhichLoader = union(enum) {
    bootstrap,
    user: VmObjectRef,

    fn eq(a: @This(), b: @This()) bool {
        return switch (a) {
            .bootstrap => switch (b) {
                .bootstrap => true,
                else => false,
            },
            .user => |obj_a| switch (b) {
                .user => |obj_b| obj_a.cmpPtr(obj_b),
                else => false,
            },
        };
    }

    fn clone(self: @This()) @This() {
        return switch (self) {
            .bootstrap => .bootstrap,
            .user => |obj| .{ .user = obj.clone() },
        };
    }

    fn deinit(self: @This()) void {
        switch (self) {
            .user => |obj| obj.drop(),
            .bootstrap => {},
        }
    }
};
pub const ClassLoader = struct {
    const Self = @This();

    alloc: Allocator,

    /// Protects classes map
    lock: Thread.RwLock,
    classes: std.ArrayHashMapUnmanaged(Key, LoadState, ClassesContext, true),

    // Protects native libs map
    natives_lock: Thread.RwLock,
    natives: std.AutoHashMapUnmanaged(WhichLoader, native.NativeLibraries),

    this_native: native.NativeLibrary,

    /// Initialised during startup so not mutex protected
    primitives: [vm_type.primitives.len]VmClassRef.Nullable = [_]VmClassRef.Nullable{VmClassRef.Nullable.nullRef()} ** vm_type.primitives.len,

    // TODO have a separate struct for cached field and method ids
    /// Set in bootstrap process
    java_lang_Class_classData: object.FieldId = undefined,

    const ClassesContext = struct {
        pub fn hash(_: @This(), key: Key) u32 {
            var hasher = std.hash.Wyhash.init(4);
            hasher.update(key.name);
            std.hash.autoHash(&hasher, key.loader);
            return @truncate(u32, hasher.final());
        }

        pub fn eql(_: @This(), a: Key, b: Key, _: usize) bool {
            return a.loader.eq(b.loader) and std.mem.eql(u8, a.name, b.name);
        }
    };

    const LoadState = union(enum) {
        unloaded,
        loading: Thread.Id,
        loaded: VmClassRef,
        failed,
    };

    const Key = struct { name: []const u8, loader: WhichLoader };

    pub fn new(alloc: Allocator) !ClassLoader {
        const this_native = try native.NativeLibrary.openSelf();
        var cl = ClassLoader{ .alloc = alloc, .lock = .{}, .classes = .{}, .natives_lock = .{}, .natives = .{}, .this_native = this_native };
        try cl.classes.ensureTotalCapacity(alloc, 1024);
        return cl;
    }

    pub fn deinit(self: *@This()) void {
        self.lock.lock();
        defer self.lock.unlock();

        // drop all class references
        {
            var it = self.classes.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                self.alloc.free(key.name);
                key.loader.deinit();
                switch (entry.value_ptr.*) {
                    .loaded => |cls| cls.drop(),
                    .failed => {}, // TODO drop exception
                    else => {},
                }
            }
        }

        self.classes.deinit(self.alloc);
        self.classes = .{};

        {
            var it = self.natives.iterator();
            while (it.next()) |e| {
                e.key_ptr.deinit();
                e.value_ptr.deinit();
            }
        }
        self.natives.deinit(self.alloc);
        self.natives = .{};

        for (self.primitives) |prim| {
            if (prim.toStrong()) |p| p.drop();
        }
    }

    /// Same as loadClass("[" ++ name, ...). Must not be a primitive
    pub fn loadClassAsArrayElement(self: *Self, elem_name: []const u8, requested_loader: WhichLoader) state.Error!VmClassRef {
        // prepend [
        var array_cls_name: []u8 = try self.alloc.alloc(u8, elem_name.len + 1);
        array_cls_name[0] = '[';
        std.mem.copy(u8, array_cls_name[1..], elem_name);
        // TODO this is leaked if the class is already loaded

        return self.loadClassInternal(array_cls_name, requested_loader, .reference);
    }

    const ArrayType = enum {
        not,
        primitive,
        reference,
    };

    /// Main entrypoint - name can be array or class name. Loads now if not already.
    /// Loader is cloned if needed for loading.
    /// Returns BORROWED reference
    pub fn loadClass(self: *Self, name: []const u8, requested_loader: WhichLoader) state.Error!VmClassRef {
        if (name.len < 1) return error.ClassFormat;

        // TODO helper wrapper type around type names like java/lang/String and [[C ?
        const array_type: ArrayType = if (name[0] == '[') blk: {
            if (name.len < 2) return error.ClassFormat;
            break :blk if (name[1] == 'L' or name[1] == '[')
                .reference
            else
                .primitive;
        } else .not;

        // use bootstrap loader for primitive arrays
        var loader = if (array_type == .primitive) .bootstrap else requested_loader;

        if (array_type == .reference) {
            // load element class first
            const elem_name = elementClassNameFromArray(name) orelse return error.ClassFormat;
            _ = try self.loadClass(elem_name, requested_loader);
        }

        return self.loadClassInternal(name, loader, array_type);
    }

    /// Must start with [ already
    fn elementClassNameFromArray(array_name: []const u8) ?[]const u8 {
        std.debug.assert(array_name[0] == '[');

        const s = array_name[1..];
        return if (s[0] == '[')
            s // nested array
        else if (s[0] == 'L') blk: {
            if (s[s.len - 1] != ';') return null;
            break :blk s[1 .. s.len - 1]; // [L...;
        } else s; // primitive
    }

    fn loadClassInternal(self: *Self, name: []const u8, loader: WhichLoader, array_type: ArrayType) state.Error!VmClassRef {
        switch (self.getLoadState(name, loader)) {
            .loading => unreachable, // TODO other threads
            .loaded => |cls| return cls,
            else => {},
        }

        // loading time
        // TODO native error to exception?
        try self.setLoadState(name, loader, .{ .loading = Thread.getCurrentId() });

        const loaded_res = switch (loader) {
            .bootstrap => if (array_type == .not) self.loadBootstrapClass(name) else self.loadArrayClass(name, array_type == .primitive, loader),
            .user => |_| {
                std.debug.assert(array_type != .primitive); // already filtered out
                unreachable; // TODO user loader
            },
        };

        if (loaded_res) |cls| {
            self.setLoadState(name, loader, .{ .loaded = cls }) catch unreachable; // already in there
            return cls;
        } else |err| {
            self.setLoadState(name, loader, .failed) catch unreachable; // already in there
            return err;
        }
    }

    fn getLoadState(self: *Self, name: []const u8, loader: WhichLoader) LoadState {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        const key = Key{ .name = name, .loader = loader };
        return self.classes.get(key) orelse .unloaded;
    }

    /// name and loader are owned by the caller, and cloned on first addition (owned by the loader).
    /// Only fails on allocating when adding new entry
    fn setLoadState(self: *Self, name: []const u8, loader: WhichLoader, load_state: LoadState) !void {
        self.lock.lock();
        defer self.lock.unlock();

        const key = Key{ .name = name, .loader = loader };
        const entry = try self.classes.getOrPut(self.alloc, key);
        if (entry.found_existing)
            entry.value_ptr.* = load_state
        else {
            entry.key_ptr.name = try self.alloc.dupe(u8, name);
            entry.key_ptr.loader = loader.clone();
        }

        std.log.debug("set {s} state for {s}", .{ @tagName(load_state), name });
    }

    /// Name is the file name of the class
    fn loadBootstrapClass(self: *Self, name: []const u8) state.Error!VmClassRef {
        // TODO should allocate in big blocks rather than using gpa for all tiny allocs
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();

        const file_bytes = try findBootstrapClassFile(arena.allocator(), self.alloc, name) orelse return error.NoClassDef;
        return self.defineClass(arena.allocator(), name, file_bytes, .bootstrap);
    }

    // TODO set exception
    fn loadArrayClass(self: *Self, name: []const u8, is_primitive: bool, loader: WhichLoader) state.Error!VmClassRef {
        std.debug.assert(name[0] == '[');
        const elem_name = elementClassNameFromArray(name) orelse return error.ClassFormat;

        const elem_class_ref = try if (is_primitive) self.loadPrimitive(elem_name) else self.loadClass(elem_name, loader);
        const elem_class = elem_class_ref.get();

        var flags = elem_class.flags;
        if (!is_primitive) flags.remove(.interface) else flags.insert(.public);
        flags.insert(.abstract);
        flags.insert(.final);

        // TODO faster lookup
        const java_lang_Object = self.getLoadedBootstrapClass("java/lang/Object") orelse unreachable;

        // TODO interfaces cloneable and serializable
        const elem_dims = if (elem_class.name[0] == '[') elem_class.u.array.dims else 0;

        var class = try object.VmClassRef.new();
        errdefer class.drop();

        const padding = elem_class.calculateArrayPreElementPadding();
        class.get().* = .{
            .flags = flags,
            .name = try self.alloc.dupe(u8, name),
            .u = .{ .array = .{ .elem_cls = elem_class_ref.clone(), .dims = elem_dims + 1, .padding = padding } },
            .status = .{ .ty = .array },
            .super_cls = java_lang_Object.clone().intoNullable(),
            .interfaces = &.{}, // TODO
            .loader = loader.clone(),
            .class_instance = undefined, // set next
        };
        try self.assignClassInstance(class);

        return class;
    }

    // TODO cached/better lookup for known bootstrap classes
    /// Returns BORROWED reference
    pub fn getLoadedBootstrapClass(self: *Self, name: []const u8) ?VmClassRef {
        return switch (self.getLoadState(name, .bootstrap)) {
            .loaded => |cls| cls,
            else => null,
        };
    }

    /// Name should be static if loading for the first time (during startup).
    /// Returns BORROWED class reference
    pub fn loadPrimitive(self: *Self, name: []const u8) state.Error!VmClassRef {
        const ty = vm_type.PrimitiveDataType.fromTypeString(name) orelse std.debug.panic("invalid primitive {s}", .{name});
        return self.loadPrimitiveWithType(name, ty);
    }

    /// Must be already loaded.
    /// Returns BORROWED class reference
    pub fn getLoadedPrimitive(self: *Self, ty: vm_type.PrimitiveDataType) VmClassRef {
        var entry = &self.primitives[@enumToInt(ty)];
        return entry.toStrongUnchecked();
    }

    /// Name should be static if loading for the first time (during startup).
    /// Returns BORROWED class reference
    pub fn loadPrimitiveWithType(self: *Self, name: []const u8, ty: vm_type.PrimitiveDataType) state.Error!VmClassRef {
        var entry = &self.primitives[@enumToInt(ty)];
        if (entry.toStrong()) |cls| return cls;

        std.log.debug("loading primitive {s}", .{name});

        var class = try object.VmClassRef.new();
        errdefer class.drop();
        class.get().* = .{
            .flags = cafebabe.BitSet(cafebabe.ClassFile.Flags).init(.{
                .public = true,
                .final = true,
                .abstract = true,
            }),
            .name = name, // static
            .u = .{ .primitive = ty },
            .super_cls = VmClassRef.Nullable.nullRef(),
            .status = .{ .ty = .primitive },
            .interfaces = &.{},
            .loader = .bootstrap,
            .class_instance = undefined, // set next
        };
        try self.assignClassInstance(class);

        entry.* = class.intoNullable();
        return class; // borrowed
    }

    /// Sets class_instance field. Sets to null if java/lang/Class is not yet loaded
    pub fn assignClassInstance(self: *Self, cls: VmClassRef) error{OutOfMemory}!void {
        // instantiate class object
        const java_lang_Class = self.getLoadedBootstrapClass("java/lang/Class") orelse {
            // set to null for now
            cls.get().class_instance = VmObjectRef.Nullable.nullRef();
            return;
        };

        const class_obj = try object.VmClass.instantiateObject(java_lang_Class);

        // classdata = VmClassRef TODO is this safe?
        const fid = state.thread_state().global.classloader.java_lang_Class_classData;
        class_obj.get().getField(VmObjectRef, fid).* = cls.clone().cast(object.VmObject);

        cls.get().class_instance = class_obj.intoNullable();
    }

    /// Class bytes are the callers responsiblity to clean up.
    /// Not an array or primitive.
    fn defineClass(self: *Self, arena: Allocator, name: []const u8, class_bytes: []const u8, loader: WhichLoader) state.Error!VmClassRef {
        var stream = std.io.fixedBufferStream(class_bytes);
        var classfile = cafebabe.ClassFile.parse(arena, self.alloc, &stream) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                std.log.warn("failed to parse class file '{s}': {any}", .{ name, err });
                return error.ClassFormat;
            },
        };
        errdefer classfile.deinit(self.alloc);

        if (!std.mem.eql(u8, name, classfile.this_cls)) return error.ClassFormat;

        // linking

        // resolve super
        var super_class = if (classfile.super_cls) |super| (try self.loadClass(super, loader)).clone().intoNullable() else VmClassRef.Nullable.nullRef();

        // TODO validate superclass (5.3.5 step 3)

        var class = try object.VmClassRef.new();
        errdefer class.drop();
        class.get().* = .{
            .flags = classfile.flags,
            .name = classfile.this_cls,
            .super_cls = super_class,
            .interfaces = &.{}, // TODO
            .status = .{ .ty = .object },
            .u = .{
                .obj = .{
                    .fields = classfile.fields,
                    .methods = classfile.methods,
                    .constant_pool = classfile.constant_pool,
                    .layout = undefined, // set next in preparation stage
                },
            },
            .loader = loader.clone(),
            .class_instance = undefined, // set next
        };
        try self.assignClassInstance(class);

        // link up method class refs
        for (class.get().u.obj.methods) |_, i| {
            class.get().u.obj.methods[i].class_ref = class.clone().intoNullable();
        }

        // preparation
        var layout: object.ObjectLayout = if (classfile.flags.contains(cafebabe.ClassFile.Flags.interface)) .{} else if (super_class.toStrong()) |super| super.get().u.obj.layout else .{};
        try object.defineObjectLayout(arena, class.get().u.obj.fields, &layout);
        class.get().u.obj.layout = layout;
        std.log.debug("{s} has layout {any}", .{ name, layout });

        // TODO interfaces are not yet implemented
        classfile.interfaces.deinit(self.alloc);
        return class;
    }

    /// Arena is only used for the successfully read class file bytes
    // TODO error set and proper exception returning
    // TODO class name to path encoding
    fn findBootstrapClassFile(arena: Allocator, alloc: Allocator, name: []const u8) std.mem.Allocator.Error!?[]const u8 {
        const thread = state.thread_state();

        var buf_backing = try alloc.alloc(u8, std.fs.MAX_PATH_BYTES * 2);
        defer alloc.free(buf_backing);

        var candidate_rel = buf_backing[0..std.fs.MAX_PATH_BYTES];
        var candidate_abs = buf_backing[std.fs.MAX_PATH_BYTES .. std.fs.MAX_PATH_BYTES * 2];

        const io = struct {
            pub fn readFile(io_arena: Allocator, rel_path: []const u8, abs_path_buf: *[std.fs.MAX_PATH_BYTES]u8) ![]const u8 {
                const path_abs = try std.fs.realpath(rel_path, abs_path_buf); // TODO expand path too e.g. ~, env vars

                var file = try std.fs.openFileAbsolute(path_abs, .{});
                const sz = try file.getEndPos();

                std.log.debug("loading class file {s} ({d} bytes)", .{ path_abs, sz });
                const file_bytes = try io_arena.alloc(u8, sz);

                const n = try file.readAll(file_bytes);
                if (n != sz) std.log.warn("only read {d}/{d} bytes", .{ n, sz });
                return file_bytes;
            }
        };

        var it = thread.global.args.boot_classpath.iterator();
        return while (it.next()) |entry| {
            // TODO support zip entries
            // TODO support modules

            const path = std.fmt.bufPrint(candidate_rel, "{s}/{s}.class", .{ entry, name }) catch continue;
            // TODO why cant we open files by relative path?

            break io.readFile(arena, path, candidate_abs) catch continue;
        } else return null;
    }

    /// Loader is cloned if this is the first lib loaded by it, otherwise borrowed only
    pub fn loadNativeLibrary(self: *@This(), library: []const u8, loader: WhichLoader) !native.NativeLibrary {
        self.natives_lock.lock();
        defer self.natives_lock.unlock();

        const entry = try self.natives.getOrPut(self.alloc, loader);
        if (!entry.found_existing)
            entry.value_ptr.* = native.NativeLibraries.new(self.alloc);

        return try entry.value_ptr.lookupOrLoad(library);
    }

    pub fn loadBootstrapNativeLibrary(self: *@This()) !void {
        self.natives_lock.lock();
        defer self.natives_lock.unlock();

        const entry = try self.natives.getOrPut(self.alloc, .bootstrap);
        if (!entry.found_existing)
            entry.value_ptr.* = native.NativeLibraries.new(self.alloc);

        return try entry.value_ptr.lookupOrLoad("jvm");
    }

    pub const NativeMangling = struct {
        /// Null terminated
        buf: std.ArrayList(u8),

        pub fn escape(out: *std.ArrayList(u8), name: []const u8) !void {
            try out.ensureUnusedCapacity(name.len);

            var utf8 = (try std.unicode.Utf8View.init(name)).iterator();

            while (utf8.nextCodepointSlice()) |it| {
                switch (it.len) {
                    1 => try if (it[0] == '/') out.append('_') //
                    else if (it[0] == '_') out.appendSlice("_1") //
                    else if (it[0] == ';') out.appendSlice("_2") //
                    else if (it[0] == '[') out.appendSlice("_3") //
                    else if (it[0] == '$') out.appendSlice("_00024") //
                    else out.append(it[0]),
                    2 => {
                        const enc = try std.unicode.utf8Decode(it);
                        try out.ensureUnusedCapacity(6);
                        std.fmt.format(out.writer(), "_0{x:0>4}", .{enc}) catch unreachable;
                    },
                    else => @panic("not utf16?"),
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            self.buf.deinit();
        }

        pub fn strZ(self: *const @This()) [:0]const u8 {
            return self.buf.items[0 .. self.buf.items.len - 1 :0];
        }

        pub fn initShort(alloc: std.mem.Allocator, class_name: []const u8, method_name: []const u8) !@This() {
            var this = NativeMangling{ .buf = std.ArrayList(u8).init(alloc) };
            errdefer this.deinit();

            var writer = this.buf.writer();
            try std.fmt.format(writer, "Java_", .{});
            try escape(&this.buf, class_name);
            _ = try writer.write("_");
            try escape(&this.buf, method_name);

            // null terminate
            _ = try writer.write("\x00");
            return this;
        }

        pub fn appendLong(self: *@This(), desc: descriptor.MethodDescriptor) !void {
            // truncate null byte
            const nul = self.buf.pop();
            std.debug.assert(nul == 0);

            var writer = self.buf.writer();
            _ = try writer.write("__");
            try escape(&self.buf, desc.parameters());

            // null terminate
            _ = try writer.write("\x00");
        }
    };

    pub fn findNativeMethod(self: *@This(), loader: WhichLoader, method: *const cafebabe.Method) ?*anyopaque {
        return self.findNativeMethodInner(loader, method.class().get().name, method.name, method.descriptor);
    }

    fn findNativeMethodInner(self: *@This(), loader: WhichLoader, class_name: []const u8, method_name: []const u8, method_desc: descriptor.MethodDescriptor) ?*anyopaque {
        const Search = struct {
            fn searchLibraries(first_check: ?native.NativeLibrary, natives: ?native.NativeLibraries, name: NativeMangling) ?*anyopaque {
                const symbol = name.strZ();
                if (first_check) |lib| if (lib.resolve(symbol)) |found| return found;

                if (natives) |n| {
                    var it = n.handles.valueIterator();
                    while (it.next()) |lib|
                        if (lib.resolve(symbol)) |found| return found;
                }

                return null;
            }
        };

        var mangled_name = NativeMangling.initShort(self.alloc, class_name, method_name) catch return null;
        defer mangled_name.deinit();

        // special case, check self first
        const first_check = if (loader == .bootstrap) self.this_native else null;

        self.natives_lock.lockShared();
        defer self.natives_lock.unlockShared();
        const natives = self.natives.get(loader);

        // search for short mangled name first
        if (Search.searchLibraries(first_check, natives, mangled_name)) |found| return found;

        // try long overloaded form
        // TODO even when takes no parameters?
        mangled_name.appendLong(method_desc) catch return null;
        if (Search.searchLibraries(first_check, natives, mangled_name)) |found| return found;

        return null;
    }
};

test "native mangling class name" {
    std.testing.log_level = .debug;
    const cls_name = "my/package/MyObjêct_cool";

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();

    try ClassLoader.NativeMangling.escape(&out, cls_name);
    try std.testing.expectEqualStrings("my_package_MyObj_000eact_1cool", out.items);
}

test "native mangling full method" {
    std.testing.log_level = .debug;
    const cls_name = "my/package/Cool$Inner";
    const method = "doThings_lol";
    const desc = descriptor.MethodDescriptor.new("(ILjava/lang/String;[J)D") orelse unreachable;

    var mangled = try ClassLoader.NativeMangling.initShort(std.testing.allocator, cls_name, method);
    defer mangled.deinit();

    try std.testing.expectEqualSentinel(u8, 0, "Java_my_package_Cool_00024Inner_doThings_1lol", mangled.strZ());

    try mangled.appendLong(desc);
    try std.testing.expectEqualSentinel(u8, 0, "Java_my_package_Cool_00024Inner_doThings_1lol__ILjava_lang_String_2_3J", mangled.strZ());
}

// test "find native method in self" {
//     const S = struct {
//         export fn Java_nice_One_method() void {}
//     };

//     var loader = try ClassLoader.new(std.testing.allocator);
//     defer loader.deinit();
//     const found = loader.findNativeMethodInner(.bootstrap, "nice/One", "method", descriptor.MethodDescriptor.new("()V") orelse unreachable);
//     std.debug.assert(found != null);

// }
