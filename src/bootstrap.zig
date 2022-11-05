const std = @import("std");
const classloader = @import("classloader.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");
const state = @import("state.zig");

const Preload = struct {
    cls: []const u8,
    initialise: bool = false,
    // TODO native method bindings. use comptime reflection to link up
};

// TODO more
const preload_classes: []const Preload = &.{
    .{ .cls = "[I" },
    .{ .cls = "java/lang/System", .initialise = true },
    .{ .cls = "jdk/internal/misc/UnsafeConstants", .initialise = true },
};

pub const Options = struct {
    skip_system: bool = false,
};

fn load(opts: Options, preload: Preload, loader: *classloader.ClassLoader) !void {
    _ = opts;
    // TODO check for array
    // TODO handle user loader

    // TODO comptime check '[' and call another func. but check that all the many preload funcs share the same generated code
    // TODO variant with comptime bootstrap loader
    const cls = try loader.loadClass(preload.cls, .bootstrap);

    if (preload.initialise)
        try object.VmClass.ensureInitialised(cls);
}

fn loadPrimitives(loader: *classloader.ClassLoader) !void {
    inline for (vm_type.primitives) |prim| {
        _ = try loader.loadPrimitiveWithType(prim.name, prim.ty);
    }
}

pub fn initBootstrapClasses(loader: *classloader.ClassLoader, opts: Options) !void {
    // load special 2 first
    try load(opts, .{ .cls = "java/lang/Object" }, loader);
    try load(opts, .{ .cls = "java/lang/Class" }, loader);

    {
        const java_lang_Object = loader.getLoadedBootstrapClass("java/lang/Object").?;
        const java_lang_Class = loader.getLoadedBootstrapClass("java/lang/Class").?;

        // init cached field ids
        loader.java_lang_Class_classData = (java_lang_Class.get().findFieldRecursively("classData", "Ljava/lang/Object;", .{ .static = false }) orelse @panic("classData not found in java.lang.Class")).id;

        // fix up class vmdata pointers
        try loader.assignClassInstance(java_lang_Object);
        try loader.assignClassInstance(java_lang_Class);

        // initialise
        try object.VmClass.ensureInitialised(java_lang_Object);
        try object.VmClass.ensureInitialised(java_lang_Class);
    }

    try loadPrimitives(loader);

    // load String, special case for string pool
    try load(opts, .{ .cls = "[B" }, loader);
    try load(opts, .{ .cls = "java/lang/String", .initialise = true }, loader);

    const thread = state.thread_state();
    thread.global.string_pool.postBootstrapInit();

    inline for (preload_classes) |preload|
        try load(opts, preload, loader);

    // setup jdk/internal/misc/UnsafeConstants
    {
        const jdk_internal_misc_UnsafeConstants = loader.getLoadedBootstrapClass("jdk/internal/misc/UnsafeConstants").?;
        set_static(jdk_internal_misc_UnsafeConstants, "ADDRESS_SIZE0", @as(i32, @sizeOf(*u8)));
        set_static(jdk_internal_misc_UnsafeConstants, "PAGE_SIZE", @as(i32, std.mem.page_size));
        set_static(jdk_internal_misc_UnsafeConstants, "BIG_ENDIAN", @import("builtin").cpu.arch.endian() == .Big);
        set_static(jdk_internal_misc_UnsafeConstants, "UNALIGNED_ACCESS", false); // TODO
        set_static(jdk_internal_misc_UnsafeConstants, "DATA_CACHE_LINE_FLUSH_SIZE", @as(i32, 0)); // TODO
    }

    // setup System class
    if (!opts.skip_system) {
        {
            const java_lang_System = loader.getLoadedBootstrapClass("java/lang/System").?;
            const method = java_lang_System.get().findMethodInThisOnly("initPhase1", "()V", .{ .static = true }) orelse @panic("missing method java.lang.System::initPhase1");
            if ((try thread.interpreter.executeUntilReturn(method)) == null) {
                const exc = thread.interpreter.exception.toStrongUnchecked();
                const exc_str = object.ToString.new(thread.global.allocator.inner, exc);
                defer exc_str.deinit();
                std.log.err("initialising System threw exception {?}: \"{s}\"", .{ exc, exc_str.str });
                return error.InvocationError;
            }
        }
    }
}

fn set_static(cls: object.VmClassRef, name: []const u8, val: anytype) void {
    const val_ty = @TypeOf(val);
    const desc = switch (val_ty) {
        i32 => "I",
        bool => "Z",
        else => @compileError("bad value type"),
    };

    const field = cls.get().findFieldRecursively(name, desc, .{ .static = true }) orelse std.debug.panic("missing {s} field on {s}", .{ name, cls.get().name });
    const field_value = object.VmClass.getStaticField(val_ty, field.id);
    field_value.* = val;
    std.log.debug("set static field {s}.{s} = {any}", .{ cls.get().name, name, val });
}
