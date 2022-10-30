const classloader = @import("classloader.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");

const Preload = struct {
    cls: []const u8,
    initialise: bool = false,
    // TODO native method bindings. use comptime reflection to link up
};

// TODO more
const preload_classes: [1]Preload = .{.{ .cls = "[I" }};

pub const Options = struct {
    /// Skip initialising
    no_initialise: bool = false,
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

        // fix up class vmdata pointers
        java_lang_Object.get().class_instance = try loader.allocJavaLangClassInstance(java_lang_Object);
        java_lang_Class.get().class_instance = try loader.allocJavaLangClassInstance(java_lang_Class);

        // initialise
        try object.VmClass.ensureInitialised(java_lang_Object);
        try object.VmClass.ensureInitialised(java_lang_Class);
    }

    try loadPrimitives(loader);

    // load String, special case for string pool
    try load(opts, .{ .cls = "[B" }, loader);
    try load(opts, .{ .cls = "java/lang/String", .initialise = true }, loader);

    @import("state.zig").thread_state().global.string_pool.postBootstrapInit();

    inline for (preload_classes) |preload|
        try load(opts, preload, loader);
}
