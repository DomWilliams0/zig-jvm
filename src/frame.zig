const std = @import("std");
const cafebabe = @import("cafebabe.zig");
const object = @import("object.zig");
const desc = @import("descriptor.zig");
const types = @import("type.zig");
const Allocator = std.mem.Allocator;

pub const logging = std.debug.runtime_safety;

pub const Frame = struct {
    method: *const cafebabe.Method,
    class: object.VmClassRef, // borrowed from method

    payload: union(enum) {
        java: struct {
            operands: OperandStack,
            local_vars: LocalVars,
            code_window: [*]const u8,

            /// Used only if parent_frame is null.. pretty gross TODO
            dummy_return_slot: ?*Frame.StackEntry,
        },
        native,
    },

    parent_frame: ?*Frame,

    /// Null for native
    pub fn currentPc(self: @This()) ?u32 {
        return switch (self.payload) {
            .java => |code| blk: {
                const base = self.method.code.java.code.?; // cant be abstract
                const offset = @intFromPtr(code.code_window) - @intFromPtr(base.ptr);
                break :blk @truncate(offset);
            },
            else => null,
        };
    }

    /// Must be java and not abstract
    pub fn setPc(self: *@This(), pc: u32) void {
        std.debug.assert(self.payload == .java);
        const base = self.method.code.java.code.?; // cant be abstract
        self.payload.java.code_window = base.ptr + pc;
    }

    pub fn findExceptionHandler(self: @This(), exception: object.VmObjectRef, thread: *@import("state.zig").ThreadEnv) ?u16 {
        if (self.payload == .java) {
            const pc = self.currentPc().?;
            for (self.method.code.java.exception_handlers) |h| {
                if (!(pc >= h.start_pc and pc < h.end_pc)) continue;

                const matches = if (h.catch_type) |cls_name| blk: {
                    const handler_cls = thread.global.classloader.loadClass(cls_name, self.class.get().loader) catch return null;
                    // TODO cache this resolution in handler entry
                    break :blk object.VmClass.isInstanceOf(exception.get().class, handler_cls);
                } else true;

                if (matches) {
                    std.log.debug("found handler for exception {?} at pc {}", .{ exception, h.handler_pc });
                    return h.handler_pc;
                }
            }
        }

        return null;
    }

    // TODO move this out of frame as a generic VM type
    pub const StackEntry = struct {
        value: usize,
        ty: types.DataType,

        pub fn new(value: anytype) StackEntry {
            const val = if (@TypeOf(value) == object.VmObjectRef) value.intoNullable() else value;
            return .{ .ty = types.DataType.fromType(@TypeOf(val)), .value = convert(@TypeOf(val)).to(val) };
        }

        pub fn notPresent() StackEntry {
            return .{ .value = 0, .ty = .void };
        }

        pub fn convertTo(self: @This(), comptime T: type) T {
            if (self.ty != types.DataType.fromType(T)) typeMismatch(T, self.ty);
            return convert(T).from(self.value);
        }

        fn typeMismatch(comptime expected: type, actual: types.DataType) noreturn {
            @setCold(true);
            std.debug.panic("type mismatch, expected {s} but found {s}", .{ @typeName(expected), @tagName(actual) });
        }

        pub fn convertToInt(self: @This()) i32 {
            return if (self.ty == .byte)
                @intCast(convert(i8).from(self.value))
            else if (self.ty == .short)
                @intCast(convert(i16).from(self.value))
            else if (self.ty == .char)
                @intCast(convert(u16).from(self.value))
            else if (self.ty == .boolean)
                @intFromBool(convert(bool).from(self.value))
            else if (self.ty == .int)
                convert(i32).from(self.value)
            else
                typeMismatch(i32, self.ty);
        }

        // Doesn't check ty
        pub fn convertToUnchecked(self: @This(), comptime T: type) T {
            return convert(T).from(self.value);
        }

        fn convertToPtr(self: *@This(), comptime T: type) *T {
            if (self.ty != types.DataType.fromType(T)) typeMismatch(T, self.ty);
            return @ptrCast(&self.value);
        }

        fn convertToPtrFfi(self: *@This(), comptime T: type) *T {
            const valid = switch (T) {
                bool, i8, i16, i32, u16 => self.ty == .int,
                else => self.ty == types.DataType.fromType(T),
            };
            if (!valid) typeMismatch(T, self.ty);
            return @ptrCast(&self.value);
        }

        test "ffi ptr" {
            var e = StackEntry.new(true);
            e = StackEntry.new(e.convertToInt());
            const ptr = e.convertToPtrFfi(i8);
            try std.testing.expectEqual(ptr.*, 1);
        }

        pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            return switch (self.ty) {
                .boolean => std.fmt.format(writer, "{}", .{convert(bool).from(self.value)}),
                .byte => std.fmt.format(writer, "{}", .{convert(i8).from(self.value)}),
                .short => std.fmt.format(writer, "{}", .{convert(i16).from(self.value)}),
                .int => std.fmt.format(writer, "{}", .{convert(i32).from(self.value)}),
                .long => std.fmt.format(writer, "{}", .{convert(i64).from(self.value)}),
                .char => std.fmt.format(writer, "{}", .{convert(u16).from(self.value)}),
                .float => std.fmt.format(writer, "{}", .{convert(f32).from(self.value)}),
                .double => std.fmt.format(writer, "{}", .{convert(f64).from(self.value)}),
                .reference => std.fmt.format(writer, "{}", .{convert(object.VmObjectRef.Nullable).from(self.value)}),
                .returnAddress => std.fmt.format(writer, "{x}", .{convert(usize).from(self.value)}),
                .void => std.fmt.formatBuf("void", options, writer),
            };
        }
    };

    pub const OperandStack = struct {
        /// Points to UNINITIALISED NEXT value on stack. When full will point out of allocation
        ///  low                    high
        ///     [1, 2, 3, 4, 5, 6]
        /// idx: 0  1  2 ...    ^
        ///      ^              |
        /// bottom of stack     |
        ///                     |
        ///             top of stack
        stack: [*]StackEntry,

        bottom: [*]StackEntry,

        pub fn new(stack: [*]StackEntry) @This() {
            return .{ .stack = stack, .bottom = stack };
        }

        pub fn push(self: *@This(), value: anytype) void {
            self.pushRaw(Frame.StackEntry.new(value));
        }

        fn depth(self: @This()) usize {
            std.debug.assert(@intFromPtr(self.stack) >= @intFromPtr(self.bottom)); // stack is more than empty o_O
            return (@intFromPtr(self.stack) - @intFromPtr(self.bottom)) / @sizeOf(StackEntry);
        }

        pub fn pushRaw(self: *@This(), val: Frame.StackEntry) void {
            self.stack[0] = val;
            self.stack += 1;

            if (logging) {
                std.log.debug("operand stack: pushed #{d} ({s}): {?}", .{ self.depth() - 1, @tagName(val.ty), val });
            }
        }

        pub fn insertAt(self: *@This(), comptime idx: usize, val: Frame.StackEntry) void {
            // move up elements
            comptime var i = 1;
            inline while (i <= idx) : (i += 1) {
                const src = (self.stack - i)[0];
                const dst = &(self.stack - i + 1)[0];
                dst.* = src;
            }

            // insert new element
            (self.stack - idx)[0] = val;
            self.stack += 1;

            if (logging) {
                std.log.debug("operand stack: inserted at #{d} ({s}): {?}", .{ self.depth() - 1 - idx, @tagName(val.ty), val });
            }
        }

        pub fn dup2(self: *@This()) void {
            if (self.peekRaw().ty.isWide()) {
                // move up top element only
                self.stack[0] = (self.stack - 1)[0];
                self.stack += 1;
            } else {

                // move up top 2 elements
                self.stack[0] = (self.stack - 2)[0];
                self.stack[1] = (self.stack - 1)[0];
                self.stack += 2;
            }

            if (logging) {
                if (self.peekRaw().ty.isWide())
                    std.log.debug("operand stack: dup2 top elem ({s}): {?}", .{ @tagName(self.peekRaw().ty), self.peekRaw() })
                else
                    std.log.debug("operand stack: dup2 top elems [({s}): {?}, ({s}): {?}]", .{ @tagName(self.peekRaw().ty), self.peekRaw(), @tagName((self.stack - 2)[0].ty), (self.stack - 2)[0] });
            }
        }

        pub fn peekRawPtr(self: @This()) *Frame.StackEntry {
            std.debug.assert(!self.isEmpty());
            return &(self.stack - 1)[0];
        }

        pub fn peekRaw(self: @This()) Frame.StackEntry {
            return self.peekRawPtr().*;
        }

        /// 0 = current top, 1 = next under top
        pub fn peekAt(self: @This(), comptime T: type, idx: u16) T {
            std.debug.assert(!self.isEmpty());
            const val = (self.stack - 1 - idx)[0];
            return val.convertTo(T);
        }

        /// 0 = current top, 1 = next under top
        /// Allows i8 = bool
        pub fn peekAtPtrFfi(self: @This(), comptime T: type, idx: u16) *T {
            std.debug.assert(!self.isEmpty());
            const val = &(self.stack - 1 - idx)[0];
            return val.convertToPtrFfi(T);
        }

        fn isEmpty(self: @This()) bool {
            return self.bottom == self.stack;
        }

        pub fn clear(self: *@This()) void {
            if (logging) {
                var i: usize = self.depth();
                while (i > 0) : (i -= 1) {
                    _ = self.popRaw();
                }
            }

            std.log.debug("operand stack: cleared", .{});
            self.stack = self.bottom;
        }

        pub fn log(self: @This()) void {
            if (!logging) return;

            var i: u16 = 0;

            var buf: [1024]u8 = undefined;
            var writer = std.io.fixedBufferStream(&buf);
            _ = writer.write("operand stack: {") catch unreachable;
            const d = self.depth();
            while (i < d) {
                const ptr = self.stack - d + i;
                if (i != 0) {
                    _ = writer.write(", ") catch break;
                }
                std.fmt.format(writer.writer(), "#{d}: {s}, {?}", .{ i, @tagName(ptr[0].ty), ptr[0] }) catch break;

                i += 1;
            }

            _ = writer.write("}") catch {};

            const s = buf[0..writer.pos];
            std.log.debug("{s}", .{s});
        }

        /// Must be exact i.e. i16 != i32
        pub fn pop(self: *@This(), comptime T: type) T {
            return self.popRaw().convertTo(T);
        }

        /// Widens bool/i8/i16/u16 to i32
        pub fn popWiden(self: *@This(), comptime T: type) T {
            const val = self.popRaw();
            return if (T == i32) val.convertToInt() else val.convertTo(T);
        }

        pub fn popRaw(self: *@This()) Frame.StackEntry {
            // decrement to last value on stack
            self.stack -= 1;
            const val = self.stack[0];

            if (logging) {
                std.log.debug("operand stack: popped #{d} ({s}): {?}", .{ self.depth(), @tagName(val.ty), val });
            }
            return val;
        }

        pub fn transferToCallee(self: *@This(), callee: *LocalVars, method: desc.MethodDescriptor, implicit_this: bool) void {
            var src: u16 = 0;
            var dst: u16 = 0;
            var last_copy: u16 = 0;

            var param_count = method.param_count;
            if (implicit_this) {
                param_count += 1;
                src = 1;
            }
            const src_base = self.stack - param_count;
            var params = method.iterateParamTypes();
            while (params.next()) |param_type| {
                if (param_type.isWide()) {
                    // wide, copy everything up to here including this double
                    const n = src - last_copy + 1;
                    @memcpy(callee.vars[dst .. dst + n], src_base[last_copy .. last_copy + n]);

                    // mark as initialised for logging
                    if (logging) {
                        var i: u16 = dst;
                        while (i < dst + n) : (i += 1)
                            callee.setInitialised(i);
                    }

                    dst += n + 1;
                    src += 1;
                    last_copy = src;
                } else {
                    // keep advancing
                    src += 1;
                }
            }
            // final args
            const n = src - last_copy;
            if (n > 0) {
                @memcpy(callee.vars[dst .. dst + n], src_base[last_copy .. last_copy + n]);
                if (logging) {
                    var i: u16 = dst;
                    while (i < dst + n) : (i += 1)
                        callee.setInitialised(i);
                }
            }

            // shrink source
            self.stack -= param_count;
        }
    };

    pub const LocalVars = struct {
        vars: [*]Frame.StackEntry,

        // track initialised vars for logging
        initialised: if (logging) std.DynamicBitSet else void,

        // TODO ensure that unused alloc param when logging=false is optimised out
        pub fn new(vars: [*]Frame.StackEntry, alloc: std.mem.Allocator, n: u16) (if (logging) std.mem.Allocator.Error else error{})!@This() {
            return .{ .vars = vars, .initialised = if (logging) try std.DynamicBitSet.initEmpty(alloc, n) else {} };
        }

        fn setInitialised(self: *@This(), idx: u16) void {
            if (logging) self.initialised.set(idx);
        }

        pub fn getPtr(self: *@This(), comptime T: type, idx: u16) *T {
            return self.getRaw(idx).convertToPtr(T);
        }

        pub fn get(self: *@This(), comptime T: type, idx: u16) T {
            return self.getPtr(T, idx).*;
        }

        pub fn set(self: *@This(), value: anytype, idx: u16) void {
            self.vars[idx] = Frame.StackEntry.new(value);
            self.setInitialised(idx);
        }

        pub fn getRaw(self: *@This(), idx: u16) *Frame.StackEntry {
            return &self.vars[idx];
        }

        /// Nop if not logging
        pub fn deinit(self: *@This()) void {
            if (logging) self.initialised.deinit();
        }

        pub fn log(self: @This(), max: u16) void {
            if (!logging) return;

            const ptr = self.vars;
            _ = ptr;
            var i: u16 = 0;

            var buf: [1024]u8 = undefined;
            var written_anything = false;
            var writer = std.io.fixedBufferStream(&buf);
            _ = writer.write("local vars: [") catch unreachable;
            while (i < max) : (i += 1) {
                if (!self.initialised.isSet(i)) continue; // only log if initialised

                if (written_anything) {
                    _ = writer.write(", ") catch break;
                }
                written_anything = true;

                const lvar = self.vars[i];
                std.fmt.format(writer.writer(), "#{d}: {s}, {?}", .{ i, @tagName(lvar.ty), lvar }) catch break;
            }

            _ = writer.write("]") catch {};

            const s = buf[0..writer.pos];
            std.log.debug("{s}", .{s});
        }
    };
};

pub fn convert(comptime T: type) type {
    const u = union {
        int: usize,
        any: T,
    };
    if (@sizeOf(T) > @sizeOf(usize)) @compileError(std.fmt.comptimePrint("{s} can't be bigger than usize ({d} > {d})", .{ @typeName(T), @sizeOf(T), @sizeOf(usize) }));

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

test "convert to integer" {
    const help = struct {
        fn checkInt(
            val: anytype,
        ) void {
            const entry = Frame.StackEntry.new(val);
            const res_int = entry.convertToInt();
            const res_expected: i32 = if (@typeInfo(@TypeOf(val)) == .Bool) @intCast(@intFromBool(val)) else @intCast(val);
            std.testing.expectEqual(res_expected, res_int) catch unreachable;
        }
    };

    help.checkInt(@as(i8, 15));
    help.checkInt(@as(i8, -2));
    help.checkInt(@as(i16, 300));
    help.checkInt(@as(i16, -400));
    help.checkInt(@as(i32, 39_000));
    help.checkInt(@as(i32, -39_000));
    help.checkInt(@as(u16, 'H'));
    help.checkInt(@as(bool, true));
    help.checkInt(@as(bool, false));
}

// for both operands and localvars, alloc in big chunks
// new frame(local vars=5,)
// max_stack and max_locals known from code attr

/// Stack for operands and localvars
pub const ContiguousBufferStack = struct {
    const EACH_SIZE: usize = 4095; // leave space for `used` usize

    const Buf = struct {
        buf: [EACH_SIZE]Frame.StackEntry,
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

    pub fn reserve(self: *@This(), n: usize) ![*]Frame.StackEntry {
        var current = self.top();
        var buf: *Buf = if (current.remaining() < n)
            try self.pushNew()
        else
            current;

        const ret = buf.buf[buf.used .. buf.used + n];
        buf.used += n;

        try self.stack.append(self.bufs.allocator, .{ .ptr = @intFromPtr(ret.ptr), .len = n });

        return ret.ptr;
    }

    pub fn drop(self: *@This(), ptr: [*]Frame.StackEntry) !void {
        if (self.stack.popOrNull()) |prev| {
            if (prev.ptr == @intFromPtr(ptr)) {
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
    var backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&backing);

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

test "operands to callee local vars IDFJZS" {
    const method = desc.MethodDescriptor.new("(IDFJZS)V").?;

    // setup stack
    var o_backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&o_backing);
    stack.push(@as(i32, 10)); // bottom of stack
    stack.push(@as(f64, 44.4));
    stack.push(@as(f32, 0.25));
    stack.push(@as(i64, 500_000));
    stack.push(@as(bool, true));
    stack.push(@as(i16, 666)); // top of stack

    // setup local vars
    var o_lvars = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var vars = try Frame.LocalVars.new(&o_lvars, std.testing.allocator, 10);
    defer vars.deinit();

    stack.transferToCallee(&vars, method, false);
}

test "operands to callee local vars II" {
    const method = desc.MethodDescriptor.new("(II)V").?;

    // setup stack
    var o_backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&o_backing);
    stack.push(object.VmObjectRef.Nullable.nullRef()); // implicit this, on bottom of stack
    stack.push(@as(i32, 10));
    stack.push(@as(i32, 25)); // top of stack
    stack.log();

    // setup local vars
    var o_lvars = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var vars = try Frame.LocalVars.new(&o_lvars, std.testing.allocator, 10);
    defer vars.deinit();

    stack.transferToCallee(&vars, method, true); // implicit this

    try std.testing.expectEqual(vars.get(object.VmObjectRef.Nullable, 0), object.VmObjectRef.Nullable.nullRef());
    try std.testing.expectEqual(vars.get(i32, 1), 10);
    try std.testing.expectEqual(vars.get(i32, 2), 25);
}

test "operands to callee local vars JZ" {
    const method = desc.MethodDescriptor.new("(JZ)J").?;

    // setup stack
    var o_backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&o_backing);
    // static method so no ths
    stack.push(@as(i64, 5_000_000));
    stack.push(@as(bool, true)); // top of stack
    stack.log();

    // setup local vars
    var o_lvars = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var vars = try Frame.LocalVars.new(&o_lvars, std.testing.allocator, 10);
    defer vars.deinit();

    stack.transferToCallee(&vars, method, false); // implicit this

    try std.testing.expectEqual(vars.get(i64, 0), 5_000_000);
    try std.testing.expectEqual(vars.get(bool, 2), true);

    if (logging) {
        try std.testing.expect(vars.initialised.isSet(0));
        try std.testing.expect(!vars.initialised.isSet(1));
        try std.testing.expect(vars.initialised.isSet(2));
        try std.testing.expect(!vars.initialised.isSet(3));
    }
}

test "operand stack push and pop" {
    // setup stack
    var o_backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&o_backing);
    stack.push(@as(i32, 10)); // bottom of stack
    stack.push(@as(f64, 44.4));
    stack.push(@as(f32, 0.25));
    stack.push(@as(i64, 500_000));
    stack.push(@as(bool, true));
    stack.push(@as(i16, 666)); // top of stack

    try std.testing.expectEqual(@as(i16, 666), stack.pop(i16));
    try std.testing.expectEqual(@as(bool, true), stack.pop(bool)); // skip
    try std.testing.expectEqual(@as(i64, 500_000), stack.pop(i64));
    try std.testing.expectEqual(@as(f32, 0.25), stack.pop(f32)); // skip
    try std.testing.expectEqual(@as(f64, 44.4), stack.pop(f64));
    try std.testing.expectEqual(@as(i32, 10), stack.pop(i32));

    try std.testing.expect(stack.isEmpty());
}

test "operand stack dup2 wide" {
    // std.testing.log_level = .debug;

    // setup stack
    var o_backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&o_backing);
    stack.push(@as(i32, 10)); // bottom of stack
    stack.push(@as(f64, 44.4)); // wide at top of stack

    stack.dup2();
    stack.log();

    try std.testing.expectEqual(stack.peekAt(f64, 0), 44.4);
    try std.testing.expectEqual(stack.peekAt(f64, 1), 44.4);
    try std.testing.expectEqual(stack.peekAt(i32, 2), 10);
    try std.testing.expectEqual(stack.depth(), 3);
}

test "operand stack dup2 not wide" {
    // std.testing.log_level = .debug;

    // setup stack
    var o_backing = [_]Frame.StackEntry{Frame.StackEntry.notPresent()} ** 8;
    var stack = Frame.OperandStack.new(&o_backing);
    stack.push(@as(i32, 10)); // bottom of stack
    stack.push(@as(bool, true));
    stack.push(@as(i16, 100)); // top of stack

    stack.dup2();
    stack.log();

    try std.testing.expectEqual(stack.depth(), 5);
    try std.testing.expectEqual(stack.peekAt(i16, 0), 100);
    try std.testing.expectEqual(stack.peekAt(bool, 1), true);
    try std.testing.expectEqual(stack.peekAt(i16, 2), 100);
    try std.testing.expectEqual(stack.peekAt(bool, 3), true);
    try std.testing.expectEqual(stack.peekAt(i32, 4), 10);
}
