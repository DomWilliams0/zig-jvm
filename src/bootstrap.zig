const classloader = @import("classloader.zig");
const vm_type = @import("type.zig");

const Preload = struct {
    cls: []const u8,
    // TODO native method bindings. use comptime reflection to link up
};

const preload_classes: [1]Preload = .{.{ .cls = "java/lang/String" }};

fn load(preload: Preload, loader: *classloader.ClassLoader) !void {
    // TODO check for array
    // TODO handle user loader

    // TODO comptime check '[' and call another func. but check that all the many preload funcs share the same generated code
    // TODO variant with comptime bootstrap loader
    _ = try loader.loadClass(preload.cls, .bootstrap);
}

fn loadPrimitives(loader: *classloader.ClassLoader) !void {
    inline for (vm_type.primitives) |prim| {
        _ = try loader.loadPrimitiveWithType(prim.name, prim.ty);
    }
}

pub fn initBootstrapClasses(loader: *classloader.ClassLoader) !void {
    try load(.{ .cls = "java/lang/Object" }, loader);
    try load(.{ .cls = "java/lang/Class" }, loader);

    // TODO fix up class vmdata pointers now

    try loadPrimitives(loader);
}
