const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const object = @import("object.zig");
const desc = @import("descriptor.zig");
const Allocator = std.mem.Allocator;

pub const logging = std.log.level == .debug;

pub const Frame = struct {
    operands: OperandStack,
    local_vars: LocalVars,
    method: *const cafebabe.Method,
    class: object.VmClassRef,

    /// Null if not java method
    code_window: ?[*]const u8,

    parent_frame: ?*Frame,
    // Used only if parent_frame is null.. pretty gross TODO
    dummy_return_slot: ?*usize,

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
            self.pushAndLog(value, true);
        }

        pub fn pushRaw(self: *@This(), value: usize) void {
            self.pushAndLog(value, false);
        }

        fn pushAndLog(self: *@This(), value: anytype, comptime log: bool) void {
            // convert to usize
            // TODO check usize->usize=nop
            const val = convert(@TypeOf(value)).to(value);

            self.stack[0] = val;
            self.stack += 1;

            // TODO format input type better, e.g. dont show all fields on an object ref. but that should be the object's falut
            if (logging) {
                // set bottom on first call
                if (self.bottom_of_stack == 0)
                    self.bottom_of_stack = @ptrToInt(self.stack - 1);

                if (log)
                    std.log.debug("operand stack: pushed #{d} ({s}): {?}", .{ (@ptrToInt(self.stack - 1) - self.bottom_of_stack) / 8, @typeName(@TypeOf(value)), value })
                else
                    std.log.debug("operand stack: pushed #{d} (opaque)", .{(@ptrToInt(self.stack - 1) - self.bottom_of_stack) / 8});
            }
        }

        pub fn peekRaw(self: @This()) usize {
            if (logging) std.debug.assert(!self.isEmpty());
            return (self.stack - 1)[0];
        }

        /// 0 = current top, 1 = next under top
        pub fn peekAt(self: @This(), comptime T: type, idx: u16) T {
            if (logging) std.debug.assert(!self.isEmpty());
            const val = (self.stack - 1 - idx)[0];
            return convert(T).from(val);
        }

        fn isEmpty(self: @This()) bool {
            if (!logging) @compileError("cant check");
            return self.bottom_of_stack == 0 or self.bottom_of_stack >= @ptrToInt(self.stack);
        }

        pub fn pop(self: *@This(), comptime T: type) T {
            return self.popAndLog(T, true);
        }

        pub fn popRaw(self: *@This()) usize {
            return self.popAndLog(usize, false);
        }

        fn popAndLog(self: *@This(), comptime T: type, comptime log: bool) T {
            // decrement to last value on stack
            self.stack -= 1;
            const val_usize = self.stack[0];
            const value = convert(T).from(val_usize);

            if (logging) {
                if (self.bottom_of_stack == 0) unreachable; // should be set in push

                if (log)
                    std.log.debug("operand stack: popped #{d} ({s}): {?}", .{ (@ptrToInt(self.stack) - self.bottom_of_stack) / 8, @typeName(@TypeOf(value)), value })
                else
                    std.log.debug("operand stack: popped #{d} (opaque)", .{(@ptrToInt(self.stack) - self.bottom_of_stack) / 8});
            }
            return value;
        }

        pub fn transferToCallee(self: *@This(), callee: *LocalVars, method: desc.MethodDescriptor) void {
            // TODO cache u8 indices of wide args in method
            var src: u16 = 0;
            var dst: u16 = 0;
            var last_copy: u16 = 0;

            const src_base = self.stack - method.param_count;

            var params = method.iterateParamTypes();
            while (params.next()) |param_type| {
                if (param_type[0] == 'D' or param_type[0] == 'J') {
                    // wide, copy everything up to here including this double
                    const n = src - last_copy + 1;
                    std.mem.copy(usize, callee.vars[dst .. dst + n], src_base[last_copy .. last_copy + n]);
                    dst += n + 1;
                    src += 1;
                    last_copy = src;
                } else {
                    // keep advancing
                    src += 1;
                }
            }

            // copy final args
            const n = src - last_copy;
            std.mem.copy(usize, callee.vars[dst .. dst + n], src_base[last_copy .. last_copy + n]);

            // shrink source
            self.stack -= method.param_count;
        }
    };

    pub const LocalVars = struct {
        vars: [*]usize,
        // TODO track bounds in debug builds

        pub fn get(self: *@This(), comptime T: type, idx: u16) *T {
            return @ptrCast(*T, &self.vars[idx]);
        }

        pub fn getRaw(self: *@This(), idx: u16) *usize {
            return &self.vars[idx];
        }
    };
};

pub fn convert(comptime T: type) type {
    const u = union {
        int: usize,
        any: T,
    };
    if (@sizeOf(T) > @sizeOf(usize)) @compileError(std.fmt.comptimePrint("can't be bigger than usize ({d} > {d})", .{ @sizeOf(T), @sizeOf(usize) }));

    return struct {
        pub fn to(val: T) usize {
            @setRuntimeSafety(false);
            const x = u{ .any = val };
            return x.int;
        }

        pub fn from(val: usize) T {
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
    var backing = [_]usize{0} ** 8;
    var stack = Frame.OperandStack{ .stack = &backing };

    try std.testing.expect(stack.isEmpty());
    stack.push(@as(i32, -50));

    try std.testing.expect(!stack.isEmpty());
    try std.testing.expectEqual(@as(i32, -50), stack.peekAt(i32, 0));
    stack.push(@as(u16, 123));
    try std.testing.expect(!stack.isEmpty());
    try std.testing.expectEqual(@as(u16, 123), stack.peekAt(u16, 0));
    try std.testing.expectEqual(@as(i32, -50), stack.peekAt(i32, 1));

    try std.testing.expectEqual(@as(u16, 123), stack.pop(u16));
    try std.testing.expect(!stack.isEmpty());
    try std.testing.expectEqual(@as(i32, -50), stack.pop(i32));
    try std.testing.expect(stack.isEmpty());
}

test "operands to callee local vars" {
    const method = desc.MethodDescriptor.new("(IDFJZS)V").?;

    // setup stack
    var o_backing = [_]usize{0} ** 8;
    var stack = Frame.OperandStack{ .stack = &o_backing };
    stack.push(@as(i32, 10)); // bottom of stack
    stack.push(@as(f64, 44.4));
    stack.push(@as(f32, 0.25));
    stack.push(@as(i64, 500_000));
    stack.push(@as(bool, true));
    stack.push(@as(i16, 666)); // top of stack

    // setup local vars
    var o_lvars = [_]usize{0} ** 8;
    var vars = Frame.LocalVars{ .vars = &o_lvars };

    stack.transferToCallee(&vars, method);

    try std.testing.expectEqual(@as(i32, 10), vars.get(i32, 0).*);
    try std.testing.expectEqual(@as(f64, 44.4), vars.get(f64, 1).*);
    try std.testing.expectEqual(@as(f32, 0.25), vars.get(f32, 3).*); // skip
    try std.testing.expectEqual(@as(i64, 500_000), vars.get(i64, 4).*);
    try std.testing.expectEqual(@as(bool, true), vars.get(bool, 6).*); // skip
    try std.testing.expectEqual(@as(i16, 666), vars.get(i16, 7).*);
}

test "operands to callee local vars II" {
    const method = desc.MethodDescriptor.new("(II)V").?;

    // setup stack
    var o_backing = [_]usize{0} ** 8;
    var stack = Frame.OperandStack{ .stack = &o_backing };
    stack.push(@as(i32, 10)); // bottom of stack
    stack.push(@as(i32, 25)); // top of stack

    // setup local vars
    var o_lvars = [_]usize{0} ** 8;
    var vars = Frame.LocalVars{ .vars = &o_lvars };

    stack.transferToCallee(&vars, method);

    try std.testing.expectEqual(@as(i32, 10), vars.get(i32, 0).*);
    try std.testing.expectEqual(@as(i32, 25), vars.get(i32, 1).*);
}
