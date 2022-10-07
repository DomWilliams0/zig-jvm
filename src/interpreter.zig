const std = @import("std");
const frame = @import("frame.zig");
const cafebabe = @import("cafebabe.zig");
const insn = @import("insn.zig");
const jvm = @import("jvm.zig");
const object = @import("object.zig");

/// Each thread owns one
pub const Interpreter = struct {
    frames_alloc: frame.ContiguousBufferStack,
    top_frame: ?*frame.Frame = null,

    pub fn new(alloc: std.mem.Allocator) !Interpreter {
        return .{
            .frames_alloc = try frame.ContiguousBufferStack.new(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.frames_alloc.deinit();
    }

    pub fn executeUntilReturn(self: *@This(), class: object.VmClassRef, method: *const cafebabe.Method) !void {
        return self.executeUntilReturnWithCallerFrame(class, method, null);
    }

    pub fn executeUntilReturnWithCallerFrame(self: *@This(), class: object.VmClassRef, method: *const cafebabe.Method, caller: ?*frame.Frame.OperandStack) !void {

        // TODO format on method to show class.method
        std.log.debug("executing {s}.{s}", .{ class.get().name, method.name });
        defer std.log.debug("finished executing {s}.{s}", .{ class.get().name, method.name });

        if (method.code.code == null) @panic("TODO native method");

        // alloc local var and operand stack storage
        var operands: frame.Frame.OperandStack = undefined; // set next
        var local_vars: frame.Frame.LocalVars = undefined; // set next
        {
            const n_locals = method.code.max_locals;
            const n_operands = method.code.max_stack;

            var alloc = try self.frames_alloc.reserve(n_locals + n_operands);
            var local_vars_buf = alloc[0..n_locals];
            var operands_buf = alloc[n_locals .. n_locals + n_operands];

            operands = .{ .stack = operands_buf.ptr };
            local_vars = .{ .vars = local_vars_buf.ptr };
        }
        errdefer self.frames_alloc.drop(local_vars.vars) catch unreachable;

        // TODO handle native differently
        const code_window = method.code.code.?.ptr;

        // push args on from calling frame
        var param_count = method.descriptor.param_count;
        if (!method.flags.contains(.static)) param_count += 1; // this param
        if (param_count > 0) {
            // TODO panic/unreachable if caller stack/args not passed
            if (caller) |caller_stack| {
                caller_stack.transferToCallee(&local_vars, method.descriptor);
            }
        }

        const alloc = self.frameAllocator();
        var f = try alloc.create(frame.Frame);
        errdefer alloc.destroy(f);
        f.* = .{
            .method = method,
            .class = class.get(),
            .operands = operands,
            .local_vars = local_vars,
            .code_window = code_window,
            .parent_frame = self.top_frame,
        };

        // cant fail now, link up frame
        self.top_frame = f;

        // go go go
        std.log.debug("{?}", .{self.callstack()});
        interpreterLoop();
    }

    fn frameAllocator(self: @This()) std.mem.Allocator {
        return self.frames_alloc.bufs.allocator;
    }

    const PrintableCallStack = struct {
        top: ?*frame.Frame,
        pub fn format(self_: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            var top = self_.top;

            var i: u32 = 0;
            try std.fmt.formatBuf("call stack: ", options, writer);
            while (top) |f| {
                try std.fmt.format(writer, "\n * {d}) {s}.{s}", .{ i, f.class.name, f.method.name });
                top = f.parent_frame;
                i += 1;
            }

            _ = fmt;
        }
    };
    fn callstack(self: @This()) PrintableCallStack {
        return PrintableCallStack{ .top = self.top_frame };
    }
};

// TODO second interpreter type that generates threaded machine code for the method e.g. `call ins1 call ins2 call ins3`
//   in generated code, local var lookup should reference the caller's stack when i<param count, to avoid copying
fn interpreterLoop() void {
    const thread = jvm.thread_state();
    var ctxt_mut = insn.InsnContextMut{};
    var ctxt = insn.InsnContext{ .thread = thread, .frame = undefined, .mutable = &ctxt_mut };

    // code is verified to be correct, right? yeah...
    while (ctxt_mut.control_flow == .continue_) {
        // refetch on every insn, method might have changed
        const f = if (thread.interpreter.top_frame) |f| f else break;
        ctxt.frame = f;

        const next_insn = f.code_window.?[0];

        // lookup handler func
        const handler = insn.handler_lookup[next_insn];
        if (insn.debug_logging) std.log.debug("pc={d}: {s}", .{ ctxt.currentPc(), handler.insn_name });

        // invoke
        handler.handler(ctxt);
    }

    switch (ctxt_mut.control_flow) {
        .return_ => {
            const this_frame = thread.interpreter.top_frame.?;

            // TODO copy out return value before freeing operand stack
            if (ctxt.frame.method.descriptor.isNotVoid()) {
                const ret_value = this_frame.operands.popRaw();
                if (ctxt.frame.method.descriptor.returnType().?[0] == 'I')
                    std.log.debug("returned i32 {d}", .{frame.convert(i32).from(ret_value)});

                std.debug.panic("TODO return value {d}", .{ret_value});
            }

            // clean up this frame
            const caller_frame = this_frame.parent_frame;
            std.log.debug("returning to caller from {s}.{s}", .{ this_frame.class.name, this_frame.method.name });
            thread.interpreter.frameAllocator().destroy(this_frame);

            // pass execution back to caller
            thread.interpreter.top_frame = caller_frame;
        },

        .continue_ => unreachable,
    }
}
