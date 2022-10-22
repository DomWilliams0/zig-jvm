const jvm = @import("jvm");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const raw_args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, raw_args);

    const boot_classpath = raw_args[1];
    std.log.info("boot class path = {s}", .{boot_classpath});
    const class_name = raw_args[2];

    const bytes = try findAndReadClassFile(alloc, class_name, boot_classpath);
    var stream = std.io.fixedBufferStream(bytes);
    const cp = try jvm.cafebabe.ClassFile.parse(alloc, alloc, &stream);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("pub const methods = [_]@import(\"root.zig\").JniMethod{{\n", .{});

    for (cp.methods) |m| {
        if (m.flags.contains(.native)) {
            const mangled = try jvm.classloader.ClassLoader.NativeMangling.initShort(alloc, cp.this_cls, m.name);
            try stdout.print("    .{{.method = \"{s}\", .desc = \"{s}\"}},\n", .{ mangled.strZ(), m.descriptor.str });
        }
    }

    try stdout.print("}};\n", .{});
}

fn findAndReadClassFile(alloc: std.mem.Allocator, name: []const u8, bcp: []const u8) ![]const u8 {
    var buf_backing = try alloc.alloc(u8, std.fs.MAX_PATH_BYTES * 2);
    defer alloc.free(buf_backing);

    var candidate_rel = buf_backing[0..std.fs.MAX_PATH_BYTES];
    var candidate_abs = buf_backing[std.fs.MAX_PATH_BYTES .. std.fs.MAX_PATH_BYTES * 2];

    const io = struct {
        pub fn readFile(io_arena: std.mem.Allocator, rel_path: []const u8, abs_path_buf: *[std.fs.MAX_PATH_BYTES]u8) ![]const u8 {
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

    const full_path = try std.fmt.bufPrint(candidate_rel, "{s}/{s}.class", .{ bcp, name });
    return try io.readFile(alloc, full_path, candidate_abs);
}
