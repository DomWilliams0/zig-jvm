const std = @import("std");
const frame = @import("frame.zig");
const cafebabe = @import("../cafebabe.zig");
const insn = @import("insn.zig");

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

    pub fn executeUntilReturn(self: *@This(), method: *const cafebabe.Method) !void {
        // TODO format on method to show class.method
        std.log.debug("executing {s}", .{method.name});
        // TODO dummy frame for return value

        if (method.code.code == null) @panic("TODO native method");

        // alloc frame
        var f: frame.Frame = .{
            .method = method,
            .operands = undefined, // set here
            .local_vars = undefined, // set here
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
        errdefer self.frames_alloc.drop(f.local_vars.vars);

        // go go go
        var interp = BytecodeInterpreter{ .method = f.method };
        interp.go();
    }
};

// TODO second interpreter type that generates threaded machine code for the method e.g. `call ins1 call ins2 call ins3`
const BytecodeInterpreter = struct {
    method: *const cafebabe.Method,

    fn go(self: *@This()) void {
        // TODO can code be const actually pls
        var code = self.method.code.code orelse @panic("null code?");
        var code_window: [*]const u8 = code.ptr;

        // code is verified to be correct, right? yeah...
        while (true) {
            // TODO until control flow is implemented, bounds check
            if (@ptrToInt(code_window) >= @ptrToInt( code.ptr + code.len)) break;

            const next_insn = code_window[0];

            // lookup handler func
            const handler = insn.handler_lookup[next_insn];
            if (insn.debug_logging) std.log.debug("pc={d}: {s}", .{ self.calculatePc(code_window), handler.insn_name });

            // invoke
            code_window += 1;
            handler.handler(code_window);

            // increment
            code_window += handler.insn_size;
        }
    }

    fn calculatePc(self: @This(), window: [*]const u8) u32 {
        const base = self.method.code.code.?;
        const offset = @ptrToInt(window) - @ptrToInt(base.ptr);
        return @truncate(u32, offset);
    }
};
