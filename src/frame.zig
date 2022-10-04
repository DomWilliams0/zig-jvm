const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const Allocator = std.mem.Allocator;

pub const logging = std.log.level == .debug;

pub const Frame = struct {
    operands: OperandStack,
    local_vars: LocalVars,
    method: *const cafebabe.Method,

    parent_frame_ret_fn: *const fn (*anyopaque, u64) void,
    parent_frame_ctx: *anyopaque, // passed to ret_fn

    pub const OperandStack = struct {
        /// Points to UNINITIALISED NEXT value on stack. When full will point out of allocation
        ///  low                    high
        ///     [1, 2, 3, 4, 5, 6]
        /// idx: 0  1  2 ...    ^
        ///      ^              |
        /// bottom of stack     |
        ///                     |
        ///             top of stack
        stack: [*]usize,

        /// Used for logging only, set on first use
        bottom_of_stack: if (logging) usize else void = if (logging) 0 else {},

        pub fn push(self: *@This(), value: anytype) void {

            // cast to usize
            // TODO this wont work with longs on 32 bit so disallow that for now
            if (@sizeOf(usize) != 8) @compileError("32 bit not supported");
            const val = convert(@TypeOf(value)).to(value);

            self.stack[0] = val;
            self.stack += 1;

            // TODO format input type better, e.g. dont show all fields on an object ref. but that should be the object's falut
            if (logging) {
                // set bottom on first call
                if (self.bottom_of_stack == 0)
                    self.bottom_of_stack = @ptrToInt(self.stack - 1);
                std.log.debug("operand stack: pushed #{d} ({s}): {?}", .{ (@ptrToInt(self.stack - 1) - self.bottom_of_stack) / 8, @typeName(@TypeOf(value)), value });
            }
        }

        pub fn pop(self: *@This(), comptime T: type) T {
            // decrement to last value on stack
            self.stack -= 1;
            const val_usize = self.stack[0];
            const value = convert(T).from(val_usize);

            if (logging) {
                if (self.bottom_of_stack == 0) unreachable; // should be set in push
                std.log.debug("operand stack: popped #{d} ({s}): {?}", .{ (@ptrToInt(self.stack) - self.bottom_of_stack) / 8, @typeName(@TypeOf(value)), value });
            }
            return value;
        }
    };

    pub const LocalVars = struct {
        vars: [*]usize,
        // TODO track bounds in debug builds

        pub fn get(self: *@This(), comptime T: type, idx: u16) *T {
            return @ptrCast(*T, &self.vars[idx]);
        }
    };
};

fn convert(comptime T: type) type {
    const u = union {
        int: usize,
        any: T,
    };
    if (@sizeOf(T) > @sizeOf(usize)) @compileError("can't be bigger than usize");

    return struct {
        fn to(val: T) usize {
            @setRuntimeSafety(false);
            const x = u{ .any = val };
            return x.int;
        }
        fn from(val: usize) T {
            @setRuntimeSafety(false);
            const x = u{ .int = val };
            return x.any;
        }
    };
}

test "convert" {
    const help = struct {
        fn check(
            comptime T: type,
            val: anytype,
        ) void {
            const conv = convert(T).to(@as(T, val));
            const res = convert(T).from(conv);
            std.log.debug("{s}: {any} -> {any} -> {any}", .{ @typeName(T), val, conv, res });
            std.testing.expectEqual(res, val) catch unreachable;
        }
    };

    // int smaller than u64
    help.check(i8, -20);
    help.check(i8, 100);
    help.check(i16, -20);
    help.check(i16, 200);
    help.check(i32, -20);
    help.check(i32, 200);
    help.check(u8, 200);
    help.check(u16, 200);
    help.check(u32, 200);

    // int same size as u64
    help.check(i64, 200);
    help.check(i64, -200);
    help.check(u64, 200);

    // object ptr
    const s: []const u8 = "awesome";
    const conv = convert([*]const u8).to(s.ptr);
    const res = convert([*]const u8).from(conv);
    try std.testing.expectEqual(res, s.ptr);
}

// for both operands and localvars, alloc in big chunks
// new frame(local vars=5,)
// max_stack and max_locals known from code attr

/// Stack for operands and localvars
pub const ContiguousBufferStack = struct {
    const EACH_SIZE: usize = 4095; // leave space for `used` usize

    const Buf = struct {
        buf: [EACH_SIZE]usize,
        used: usize = 0,

        fn remaining(self: @This()) usize {
            return EACH_SIZE - self.used;
        }
    };

    /// Stack of slices of len EACH_SIZE
    bufs: std.ArrayList(*Buf),
    stack: std.ArrayListUnmanaged(struct { ptr: usize, len: usize }),

    pub const E = error{WrongPopOrder};

    pub fn new(allocator: Allocator) !ContiguousBufferStack {
        const bufs = try std.ArrayList(*Buf).initCapacity(allocator, 4);
        errdefer bufs.deinit();

        var self = ContiguousBufferStack{
            .bufs = bufs,
            .stack = .{},
        };
        _ = try self.pushNew(); // ensure at least 1
        return self;
    }

    fn pushNew(self: *@This()) !*Buf {
        var buf = try self.bufs.allocator.create(Buf);
        buf.used = 0;
        try self.bufs.append(buf);
        return buf;
    }

    fn pop(self: *@This()) void {
        const buf = self.bufs.pop();
        self.bufs.allocator.destroy(buf);
    }

    fn top(self: @This()) *Buf {
        std.debug.assert(self.bufs.items.len > 0);
        return self.bufs.items[self.bufs.items.len - 1];
    }

    pub fn deinit(self: *@This()) void {
        for (self.bufs.items) |buf| {
            self.bufs.allocator.destroy(buf);
        }

        self.stack.deinit(self.bufs.allocator);
        self.bufs.deinit();
    }

    pub fn reserve(self: *@This(), n: usize) ![*]usize {
        var current = self.top();
        var buf: *Buf = if (current.remaining() < n)
            try self.pushNew()
        else
            current;

        var ret = buf.buf[buf.used .. buf.used + n];
        buf.used += n;

        try self.stack.append(self.bufs.allocator, .{ .ptr = @ptrToInt(ret.ptr), .len = n });

        return ret.ptr;
    }

    pub fn drop(self: *@This(), ptr: [*]usize) !void {
        if (self.stack.popOrNull()) |prev| {
            if (prev.ptr == @ptrToInt(ptr)) {
                // nice, it matches
                var buf = self.top();
                if (prev.len >= buf.used) {
                    // top is now empty
                    // TODO dont flush immediately, keep allocation until the next push? or not worth
                    self.pop();
                } else {
                    buf.used -= prev.len;
                }

                return; // success
            }
        }

        return error.WrongPopOrder;
    }
};

test "contiguous bufs" {
    var buffers = try ContiguousBufferStack.new(std.testing.allocator);
    defer buffers.deinit();

    _ = try buffers.reserve(96); // fits into current
    _ = try buffers.reserve(3000); // still fits into current
    _ = try buffers.reserve(990); // still fits into current
    try std.testing.expectEqual(buffers.bufs.items.len, 1);

    // needs a new one
    const b = try buffers.reserve(20);
    try std.testing.expectEqual(buffers.bufs.items.len, 2);
    const c = try buffers.reserve(200);
    try std.testing.expectEqual(buffers.bufs.items.len, 2);

    // pop in same order
    try buffers.drop(c);
    try std.testing.expectEqual(buffers.bufs.items.len, 2); // still needs for b
    try buffers.drop(b);
    // buffers.flushNow(); // force flush now
    try std.testing.expectEqual(buffers.bufs.items.len, 1); // popped
}

test "contiguous bufs pop wrong order" {
    var buffers = try ContiguousBufferStack.new(std.testing.allocator);
    defer buffers.deinit();

    const a = try buffers.reserve(50);
    const b = try buffers.reserve(50);
    try std.testing.expectError(error.WrongPopOrder, buffers.drop(a)); // should pop b first
    _ = b;
}

test "operand stack" {
    std.testing.log_level = .debug;
    var backing = [_]usize{0} ** 8;
    var stack = Frame.OperandStack{ .stack = &backing };

    stack.push(@as(i32, -50));
    stack.push(@as(u16, 123));

    try std.testing.expectEqual(@as(u16, 123), stack.pop(u16));
    try std.testing.expectEqual(@as(i32, -50), stack.pop(i32));
}
