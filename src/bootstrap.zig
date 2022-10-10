const classloader = @import("classloader.zig");
const vm_type = @import("type.zig");
const object = @import("object.zig");

const Preload = struct {
    cls: []const u8,
    initialise: bool = false,
    // TODO native method bindings. use comptime reflection to link up
};

const preload_classes: [2]Preload = .{ .{ .cls = "java/lang/String" }, .{ .cls = "[I" } };

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
        object.VmClass.ensureInitialised(cls);
}

fn loadPrimitives(loader: *classloader.ClassLoader) !void {
    inline for (vm_type.primitives) |prim| {
        _ = try loader.loadPrimitiveWithType(prim.name, prim.ty);
    }
}

pub fn initBootstrapClasses(loader: *classloader.ClassLoader, comptime opts: Options) !void {
    try load(opts, .{ .cls = "java/lang/Object", .initialise = true }, loader);
    try load(opts, .{ .cls = "java/lang/Class", .initialise = true }, loader);

    // TODO fix up class vmdata pointers now

    try loadPrimitives(loader);
    inline for (preload_classes) |preload|
        try load(opts, preload, loader);
}
