const std = @import("std");
const frame = @import("frame.zig");
const cafebabe = @import("cafebabe.zig");
const insn = @import("insn.zig");
const jvm = @import("jvm.zig");
const object = @import("object.zig");

const DummyReturnValue = struct {
    returned: u64 = undefined,

    fn return_fn(self: *anyopaque, val: u64) void {
        var self_mut = @ptrCast(*@This(), @alignCast(@alignOf(@This()), self));
        self_mut.returned = val;
        std.log.debug("dummy frame received return value {x}", .{val});
    }
};

pub const Interpreter = struct {
    frames_alloc: frame.ContiguousBufferStack,

    pub fn new(alloc: std.mem.Allocator) !Interpreter {
        return .{
            .frames_alloc = try frame.ContiguousBufferStack.new(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.frames_alloc.deinit();
    }

    pub fn executeUntilReturn(self: *@This(), class: object.VmClassRef, method: *const cafebabe.Method) !void {
        // TODO format on method to show class.method
        std.log.debug("executing {s}.{s}", .{ class.get().name, method.name });
        defer std.log.debug("finished executing {s}.{s}", .{ class.get().name, method.name });

        if (method.code.code == null) @panic("TODO native method");

        // alloc frame with dummy return slot
        var dummy_return = DummyReturnValue{};
        var f = try self.frames_alloc.bufs.allocator.create(frame.Frame);
        errdefer self.frames_alloc.bufs.allocator.destroy(f);
        f.* = .{
            .method = method,
            .parent_frame_ret_fn = DummyReturnValue.return_fn,
            .parent_frame_ctx = &dummy_return,
            .operands = undefined, // set next
            .local_vars = undefined, // set next
        };
        {
            const n_locals = method.code.max_locals;
            const n_operands = method.code.max_stack;

            var alloc = try self.frames_alloc.reserve(n_locals + n_operands);
            var local_vars_buf = alloc[0..n_locals];
            var operands_buf = alloc[n_locals .. n_locals + n_operands];

            f.operands = .{ .stack = operands_buf.ptr };
            f.local_vars = .{ .vars = local_vars_buf.ptr };
        }
        errdefer self.frames_alloc.drop(f.local_vars.vars) catch unreachable;

        // go go go
        var interp = BytecodeInterpreter{ .method = f.method, .class = class, .frame = f };
        interp.go();
    }
};

// TODO second interpreter type that generates threaded machine code for the method e.g. `call ins1 call ins2 call ins3`
const BytecodeInterpreter = struct {
    method: *const cafebabe.Method,
    class: object.VmClassRef,
    frame: *frame.Frame,

    fn go(self: *@This()) void {
        const code = self.method.code.code orelse @panic("null code?");
        var code_window: [*]const u8 = code.ptr;

        var state = insn.InsnContext{
            .thread = jvm.thread_state(),
            .constant_pool = &self.class.get().constant_pool,
            .loader = self.class.get().loader,
            .operands = self.frame.operands,
            .local_vars = self.frame.local_vars,
        };

        // code is verified to be correct, right? yeah...
        while (true) {
            const next_insn = code_window[0];

            // lookup handler func
            const handler = insn.handler_lookup[next_insn];
            if (insn.debug_logging) std.log.debug("pc={d}: {s}", .{ self.calculatePc(code_window), handler.insn_name });

            // invoke
            handler.handler(&code_window, &state);
        }
    }

    fn calculatePc(self: @This(), window: [*]const u8) u32 {
        const base = self.method.code.code.?;
        const offset = @ptrToInt(window) - @ptrToInt(base.ptr);
        return @truncate(u32, offset);
    }
};
