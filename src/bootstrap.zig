const std = @import("std");
const classloader = @import("classloader.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");
const state = @import("state.zig");
const call = @import("call.zig");

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

    // load String and Thread
    try load(opts, .{ .cls = "[B" }, loader);
    try load(opts, .{ .cls = "java/lang/String", .initialise = true }, loader);
    try load(opts, .{ .cls = "java/lang/Thread", .initialise = true }, loader);
    try load(opts, .{ .cls = "java/lang/ThreadGroup", .initialise = true }, loader);

    const thread = state.thread_state();
    try thread.global.postBootstrapInit();

    inline for (preload_classes) |preload|
        try load(opts, preload, loader);

    // setup jdk/internal/misc/UnsafeConstants
    {
        const jdk_internal_misc_UnsafeConstants = loader.getLoadedBootstrapClass("jdk/internal/misc/UnsafeConstants").?;
        call.setStaticFieldInfallible(jdk_internal_misc_UnsafeConstants, "ADDRESS_SIZE0", "I", @as(i32, @sizeOf(*u8)));
        call.setStaticFieldInfallible(jdk_internal_misc_UnsafeConstants, "PAGE_SIZE", "I", @as(i32, std.mem.page_size));
        call.setStaticFieldInfallible(jdk_internal_misc_UnsafeConstants, "BIG_ENDIAN", "Z", @import("builtin").cpu.arch.endian() == .big);
        call.setStaticFieldInfallible(jdk_internal_misc_UnsafeConstants, "UNALIGNED_ACCESS", "Z", false); // TODO
        call.setStaticFieldInfallible(jdk_internal_misc_UnsafeConstants, "DATA_CACHE_LINE_FLUSH_SIZE", "I", @as(i32, 0)); // TODO
    }

    // setup System class
    if (!opts.skip_system) {
        // required early on before jdk/internal/reflect/Reflection.<clinit>
        try load(opts, .{ .cls = "java/lang/reflect/AccessibleObject", .initialise = true }, loader);

        const java_lang_System = loader.getLoadedBootstrapClass("java/lang/System").?;

        // phase1
        const init_phase1 = java_lang_System.get().findMethodInThisOnly("initPhase1", "()V", .{ .static = true }) orelse @panic("missing method java.lang.System::initPhase1");
        if ((try thread.interpreter.executeUntilReturn(init_phase1)) == null) {
            const exc = thread.interpreter.exception().toStrongUnchecked();
            call.logExceptionWithCause(thread, "initialising System phase1", exc);
            return error.InvocationError;
        }

        const init_phase2 = java_lang_System.get().findMethodInThisOnly("initPhase2", "(ZZ)I", .{ .static = true }) orelse @panic("missing method java.lang.System::initPhase2");
        if (try thread.interpreter.executeUntilReturn(init_phase2)) |ret| {
            if (ret.convertToInt() != @import("sys/jni.zig").JNI_OK) {
                std.log.err("System::initPhase2 failed", .{});
                return error.Internal;
            }
        } else {
            const exc = thread.interpreter.exception().toStrongUnchecked();
            call.logExceptionWithCause(thread, "initialising System phase2", exc);
            return error.InvocationError;
        }
    }
}
