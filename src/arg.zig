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

// TODO make a tagged union, if has no field then takesvalue=false
const ArgType = enum {
    classpath,
    bootclasspath,
    help,
    main_class, // positional

    fn takesValue(self: @This()) bool {
        return switch (self) {
            .classpath => true,
            .bootclasspath => true,
            .help => false,
            .main_class => false, // positional
        };
    }
};

const args_def = [_]Arg{
    Arg{ .name = "cp", .short = true, .ty = .classpath },
    Arg{ .name = "classpath", .short = false, .ty = .classpath },

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
        indices: std.ArrayList(u32),

        // TODO iterate helper
    };

    /// Args must live as long as this.
    /// If returns null, show usage
    pub fn parse(alloc: Allocator, args: []const [:0]const u8) ?JvmArgs {
        _ = alloc;
        _ = args;
        return null;
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
                const key = arg[arg_cursor .. key_end_idx];

                const arg_def = match_arg(key, arg_cursor == 1) orelse return null;
                if (arg_def.ty.takesValue()) {
                    if (contains_value) {
                        // value is contained in this arg already
                        const value = arg[key_end_idx+1..];
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
    std.testing.log_level = .debug;

    const args = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp", "a:b:c", "-h", "positional" }) orelse unreachable;
    try std.testing.expectEqualStrings(args.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqual(args.get(ArgType.help).?, null);
    try std.testing.expectEqualStrings(args.get(ArgType.main_class).?.?, "positional");
}

test "long/short key values" {
    std.testing.log_level = .debug;

    const a = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp", "a:b:c"}) orelse unreachable;
    const b = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp:a:b:c"}) orelse unreachable; // odd but meh
    const c = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath=a:b:c"}) orelse unreachable;
    const d = JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath", "a:b:c"}) orelse unreachable; 

    try std.testing.expectEqualStrings(a.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqualStrings(b.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqualStrings(c.get(ArgType.classpath).?.?, "a:b:c");
    try std.testing.expectEqualStrings(d.get(ArgType.classpath).?.?, "a:b:c");
}

test "bad" {
    std.testing.log_level = .debug;
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath="}));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "-cp:"}));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath"}));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm", "--classpath", "--classpath"}));
    try std.testing.expectEqual(null, JvmArgs.do_parse(&[_][:0]const u8{ "jvm"}));
}