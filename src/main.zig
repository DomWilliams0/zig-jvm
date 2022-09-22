const std = @import("std");
const cafebabe = @import("cafebabe.zig");

pub const JvmError = error{
    BadArgs,
};

pub const log_level: std.log.Level = .debug;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const path = if (args.len != 2) return JvmError.BadArgs else args[1];


    var arena_alloc = std.heap.ArenaAllocator.init(alloc);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();
    _ = try cafebabe.ClassFile.load(arena, alloc, path);

    std.log.info("done", .{});
}
