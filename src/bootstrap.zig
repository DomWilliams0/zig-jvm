const classloader = @import("classloader.zig");

const Preload = struct {
    cls: []const u8,
    // TODO native method bindings. use comptime reflection to link up
};

const preload_classes: [1]Preload = .{.{ .cls = "java/lang/String" }};

fn load(preload: Preload, loader: *classloader.ClassLoader) void {
    _ = preload;
    _=loader;
}

pub fn initBootstrapClasses(loader: *classloader.ClassLoader) void {
    load(.{ .cls = "java/lang/Object" }, loader);
    load(.{ .cls = "java/lang/Class" }, loader);

    @panic("nice"); // TODO
}
