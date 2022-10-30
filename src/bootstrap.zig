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
const preload_classes: [2]Preload = .{ .{ .cls = "[I" }, .{ .cls = "java/lang/System", .initialise = true } };

pub const Options = struct {
    /// Skip initialising
    no_initialise: bool = false,

    skip_system: bool = false,
};

fn load(comptime opts: Options, preload: Preload, loader: *classloader.ClassLoader) !void {
    // TODO check for array
    // TODO handle user loader

    // TODO comptime check '[' and call another func. but check that all the many preload funcs share the same generated code
    // TODO variant with comptime bootstrap loader
    const cls = try loader.loadClass(preload.cls, .bootstrap);

    if (!opts.no_initialise and preload.initialise)
        try object.VmClass.ensureInitialised(cls);
}

fn loadPrimitives(loader: *classloader.ClassLoader) !void {
    inline for (vm_type.primitives) |prim| {
        _ = try loader.loadPrimitiveWithType(prim.name, prim.ty);
    }
}

pub fn initBootstrapClasses(loader: *classloader.ClassLoader, comptime opts: Options) !void {
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

    // setup System class
    if (!opts.skip_system) {
        const java_lang_System = loader.getLoadedBootstrapClass("java/lang/System").?;
        const method = java_lang_System.get().findMethodInThisOnly("initPhase1", "()V", .{ .static = true }) orelse @panic("missing method java.lang.System::initPhase1");
        if ((try thread.interpreter.executeUntilReturn(java_lang_System, method)) == null) {
            const exc = thread.interpreter.exception.toStrongUnchecked();
            const exc_str = exceptionToString(exc);
            std.log.err("initialising System threw exception {?}: \"{s}\"", .{ exc, exc_str });
            return error.InvocationError;
        }
    }
}

pub fn exceptionToString(exc: object.VmObjectRef) []const u8 {
    const ERR = "<error calling toString>";
    const exc_str_obj = (object.VmObject.toString(exc) catch return ERR).toStrong() orelse return ERR;
    return exc_str_obj.get().getStringValue() orelse ERR;
}
