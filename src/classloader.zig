const std = @import("std");
const Allocator = std.mem.Allocator;

// TODO move to own module
// pub fn VmRef(comptime T: type) type{
//     return struct {

//     };
// }

pub const WhichLoader = union(enum) {
    bootstrap,
    // user:

};

pub const ClassLoader = struct {
    pub const LoadContext = struct {};

    pub fn new(alloc: Allocator) !ClassLoader {
        _ = alloc;
        return ClassLoader{};
    }
};
