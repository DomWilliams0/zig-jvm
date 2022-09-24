const std = @import("std");
const root = @import("root");
const io = std.io;
const log = std.log;
const Allocator = std.mem.Allocator;

const Arg = struct {
    name: []const u8,
    short: bool,
    ty: ArgType,
};

const ArgType = enum {
    classpath,
    bootclasspath,
    help,
    main_class, // positional

    fn takesValue(self: @This()) bool {
        const take_value = std.EnumSet(ArgType).init(.{ .classpath = true, .bootclasspath = true });
        return take_value.contains(self);
    }
};

const args_def = [_]Arg{
    Arg{ .name = "cp", .short = true, .ty = .classpath },
    Arg{ .name = "classpath", .short = false, .ty = .classpath },

    // TODO needs /p or /a
    Arg{ .name = "Xbootclasspath", .short = true, .ty = .bootclasspath },

    Arg{ .name = "h", .short = true, .ty = .help },
    Arg{ .name = "help", .short = true, .ty = .help },
    Arg{ .name = "help", .short = false, .ty = .help },
};

pub const JvmArgs = struct {
    argv: []const [:0]const u8,
    classpath: Classpath,
    boot_classpath: Classpath,
    main_class: []const u8,

    const Classpath = struct {
        const Elem = struct { idx: u32, len: u32 };
        indices: std.ArrayList(Elem),
        slice: ?[]const u8,

        fn new(alloc: Allocator) @This() {
            return .{ .indices = std.ArrayList(Elem).init(alloc), .slice = null };
        }

        fn initWith(self: *@This(), path: []const u8) !void {
            if (self.slice != null) @panic("call only once");
            self.slice = path;
            try self.indices.ensureTotalCapacity(16);
            var it = std.mem.split(u8, path, ":");
            while (it.next()) |s| {
                const idx = @ptrToInt(s.ptr) - @ptrToInt(path.ptr);
                const len = s.len;
                try self.indices.append(.{ .idx = @truncate(u32, idx), .len = @truncate(u32, len) });
            }
        }

        fn deinit(self: *@This()) void {
            self.indices.deinit();
        }

        const ClasspathIterator = struct {
            cp: *const Classpath,
            next_idx: u32,

            pub fn next(self: *@This()) ?[]const u8 {
                const idx = self.next_idx;
                if (idx >= self.cp.indices.items.len) return null;
                self.next_idx += 1;

                const elem = self.cp.indices.items[idx];
                return self.cp.slice.?[elem.idx .. elem.idx + elem.len];
            }
        };

        pub fn iterator(self: *const @This()) ClasspathIterator {
            return .{ .cp = self, .next_idx = 0 };
        }
    };

    /// Args must live as long as this.
    /// If returns null, show usage
    pub fn parse(alloc: Allocator, args: []const [:0]const u8) !?JvmArgs {
        const parsed = do_parse(args) orelse return null;

        // abort on help
        if (parsed.contains(.help)) return null;

        var classpath = Classpath.new(alloc);
        var boot_classpath = Classpath.new(alloc);
        var main_class: []const u8 = undefined;

        if (parsed.get(.main_class)) |cls| {
            main_class = cls.?;
        } else {
            return null;
        }

        if (parsed.get(.classpath)) |cp_s| {
            try classpath.initWith(cp_s.?);
        }
        if (parsed.get(.bootclasspath)) |cp_s| {
            try boot_classpath.initWith(cp_s.?);
        }

        return .{ .argv = args, .classpath = classpath, .boot_classpath = boot_classpath, .main_class = main_class };
    }

    /// Args must live as long as this.
    /// If returns null, show usage
    fn do_parse(args: []const [:0]const u8) ?std.EnumMap(ArgType, ?[]const u8) {
        if (args.len <= 1) return null;

        const State = enum {
            new_arg,
            value, // TODO tagged union with argtype, currently not implemented 22/09/22
        };
        var next_value: ?ArgType = null;

        var cursor: usize = 1; // skip argv0
        var state = State.new_arg;

        var results = std.EnumMap(ArgType, ?[]const u8).init(.{});

        while (cursor < args.len) {
            // TODO make more data oriented to support more
            // TODO perfect hash?

            const arg = args[cursor];

            if (state == .new_arg and arg.len > 1 and arg[0] == '-') {
                var arg_cursor: usize = undefined;
                var delim: u8 = undefined;

                if (arg[1] == '-') {
                    // long arg, read to '='
                    arg_cursor = 2;
                    delim = '=';
                } else {
                    // short arg, read to ':'
                    arg_cursor = 1;
                    delim = ':';
                }

                const key_end_idx_offset = std.mem.indexOfScalar(u8, arg[arg_cursor..], delim);
                var key_end_idx: usize = undefined;
                if (key_end_idx_offset) |off| {
                    key_end_idx = off + arg_cursor;
                } else {
                    key_end_idx = arg.len;
                }
                const contains_value = key_end_idx_offset != null;
                const key = arg[arg_cursor..key_end_idx];

                const arg_def = match_arg(key, arg_cursor == 1) orelse return null;
                if (arg_def.ty.takesValue()) {
                    if (contains_value) {
                        // value is contained in this arg already
                        const value = arg[key_end_idx + 1 ..];
                        results.put(arg_def.ty, value);
                    } else {
                        // expect value next arg
                        state = .value;
                        next_value = arg_def.ty;
                    }
                } else {
                    // just a flag, done
                    results.put(arg_def.ty, null);
                }
            } else if (state == .value) {
                // value of prev arg
                results.put(next_value.?, arg);
                state = .new_arg;
                next_value = null;
            } else {
                // pos arg
                results.put(ArgType.main_class, arg);
            }

            cursor += 1;
        }

        return results;
    }

    fn deinit(self: *@This()) void {
        self.boot_classpath.deinit();
        self.classpath.deinit();
    }
};

fn match_arg(s: []const u8, short: bool) ?*const Arg {
    // TODO perfect hash or at least binary sort
    inline for (args_def) |arg| {
        if (arg.short == short and std.mem.eql(u8, s, arg.name))
            return &arg;
    }

    return null;
}

test "simple" {
    const args = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp", "a:b:c", "-h", "positional" }) orelse unreachable;
    try std.testing.expectEqualStrings(args.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqual(args.get(ArgType.help).?, null);
    try std.testing.expectEqualStrings(args.get(ArgType.main_class).?.?, "positional");
}

test "long/short key values" {
    const a = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp", "a:b:c" }) orelse unreachable;
    const b = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp:a:b:c" }) orelse unreachable; // odd but meh
    const c = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath=a:b:c" }) orelse unreachable;
    const d = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath", "a:b:c" }) orelse unreachable;

    try std.testing.expectEqualStrings(a.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqualStrings(b.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqualStrings(c.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqualStrings(d.get(ArgType.classpath).?.?, "a:b:c");
}

test "bad" {
    // std.testing.log_level = .debug;
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath=" }));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp:" }));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath" }));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath", "--classpath" }));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{"jvm"}));
}

test "load and parse" {
    // std.testing.log_level = .debug;
    var args = try JvmArgs.parse(std.testing.allocator, &[_][:0]const u8{ "jvm", "-cp", "/nice:cool/epic/sweet.jar:lalala", "positional" }) orelse unreachable;
    defer args.deinit();

    var cp = args.classpath.iterator();
    try std.testing.expectEqualStrings("/nice", cp.next().?);
    try std.testing.expectEqualStrings("cool/epic/sweet.jar", cp.next().?);
    try std.testing.expectEqualStrings("lalala", cp.next().?);
    try std.testing.expectEqual(null, cp.next());
}
