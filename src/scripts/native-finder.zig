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

    if (std.mem.eql(u8, class_name, "-")) {
        // read many and output to a directory
        const out_dir_rel = raw_args[3];
        const out_dir_abs = try std.fs.realpathAlloc(alloc, out_dir_rel);
        defer alloc.free(out_dir_abs);

        const stdin = std.io.getStdIn();
        const lines = stdin.reader();
        var buf: [1024]u8 = undefined;
        while (try lines.readUntilDelimiterOrEof(&buf, '\n')) |cls_full| {
            const cls = if (std.mem.endsWith(u8, cls_full, ".class")) cls_full[0 .. cls_full.len - 6] else cls_full;
            var cls_enc_arr = std.ArrayList(u8).init(alloc);
            try jvm.classloader.ClassLoader.NativeMangling.escape(&cls_enc_arr, cls);
            try cls_enc_arr.appendSlice(".zig");

            const file_path = try std.fs.path.join(alloc, &.{ out_dir_abs, cls_enc_arr.items });
            var file = try std.fs.createFileAbsolute(file_path, .{});
            var writer = file.writer();
            try writer.writeAll(
                \\const std = @import("std");
                \\const jvm = @import("jvm");
                \\const jni = jvm.jni;
                \\const sys = jni.sys;
                \\const JniEnvPtr = jvm.jni.JniEnvPtr;
                \\
                \\
            );

            const any = extractNatives(alloc, cls, boot_classpath, writer) catch false;
            file.close();
            if (!any) try std.fs.deleteFileAbsolute(file_path);
        }
    } else {
        // read single
        const stdout = std.io.getStdOut().writer();
        _ = try extractNatives(alloc, class_name, boot_classpath, stdout);
    }
}

fn extractNatives(alloc: std.mem.Allocator, class_name: []const u8, boot_classpath: []const u8, writer: anytype) !bool {
    const bytes = try findAndReadClassFile(alloc, class_name, boot_classpath);
    var stream = std.io.fixedBufferStream(bytes);
    const cp = try jvm.cafebabe.ClassFile.parse(alloc, alloc, &stream);

    try writer.print("pub const methods = [_]@import(\"root.zig\").JniMethod{{\n", .{});

    var any = false;
    for (cp.methods) |m| {
        if (m.flags.contains(.native)) {
            any = true;
            const mangled = try jvm.classloader.ClassLoader.NativeMangling.initShort(alloc, cp.this_cls, m.name);
            try writer.print("    .{{.method = \"{s}\", .desc = \"{s}\"}},\n", .{ mangled.strZ(), m.descriptor.str });
        }
    }

    try writer.print("}};\n", .{});
    return any;
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
