const std = @import("std");
const frame = @import("frame.zig");
const cafebabe = @import("cafebabe.zig");
const insn = @import("insn.zig");
const state = @import("state.zig");
const object = @import("object.zig");

/// Each thread owns one
pub const Interpreter = struct {
    frames_alloc: frame.ContiguousBufferStack,
    top_frame: ?*frame.Frame = null,
    /// Owned instance of current exception, don't overwrite directly
    exception: object.VmObjectRef.Nullable,

    pub fn new(alloc: std.mem.Allocator) !Interpreter {
        return .{
            .frames_alloc = try frame.ContiguousBufferStack.new(alloc),
            .exception = object.VmObjectRef.Nullable.nullRef(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.frames_alloc.deinit();
    }

    /// Returns null if an exception was thrown
    pub fn executeUntilReturn(self: *@This(), class: object.VmClassRef, method: *const cafebabe.Method) state.Error!?frame.Frame.StackEntry {
        return self.executeUntilReturnWithCallerFrame(class, method, null);
    }

    /// Returns null if an exception was thrown
    pub fn executeUntilReturnWithCallerFrame(self: *@This(), class: object.VmClassRef, method: *const cafebabe.Method, caller: ?*frame.Frame.OperandStack) state.Error!?frame.Frame.StackEntry {
        // TODO format on method to show class.method
        std.log.debug("executing {s}.{s}", .{ class.get().name, method.name });
        defer std.log.debug("finished executing {s}.{s}", .{ class.get().name, method.name });

        switch (method.code) {
            .native => |native| {
                var native_mut = native;
                var code = try native_mut.ensure_bound(class, method);

                const static_cls = if (method.flags.contains(.static))
                    class.get().getClassInstance()
                else
                    null;

                const caller_stack = caller orelse @panic("native method requires caller stack");

                // ready to call, create frame now
                const alloc = self.frameAllocator();
                var f = try alloc.create(frame.Frame);
                errdefer alloc.destroy(f);
                f.* = .{
                    .method = method,
                    .class = class.clone(),
                    .payload = .{ .native = {} },
                    .parent_frame = self.top_frame,
                };
                self.top_frame = f;

                // invoke native method
                std.log.debug("{?}", .{self.callstack()});
                code.invoke(caller_stack, static_cls);

                // cleanup
                popFrame(f, state.thread_state());

                // exception check
                if (state.checkException()) return null;

                // native must have a caller, so return value is ignored
                std.debug.assert(self.top_frame != null);
                return frame.Frame.StackEntry.notPresent();
            },

            .java => |code| {
                // alloc local var and operand stack storage
                var operands: frame.Frame.OperandStack = undefined; // set next
                var local_vars: frame.Frame.LocalVars = undefined; // set next
                {
                    const n_locals = code.max_locals;
                    const n_operands = code.max_stack;

                    var alloc = try self.frames_alloc.reserve(n_locals + n_operands);
                    var local_vars_buf = alloc[0..n_locals];
                    var operands_buf = alloc[n_locals .. n_locals + n_operands];

                    operands = frame.Frame.OperandStack.new(operands_buf.ptr);
                    local_vars = try frame.Frame.LocalVars.new(local_vars_buf.ptr, self.frameAllocator(), n_locals);
                }
                errdefer self.frames_alloc.drop(local_vars.vars) catch unreachable;

                const code_slice = code.code orelse @panic("abstract method");
                const code_window = code_slice.ptr;

                // push args on from calling frame
                var param_count = method.descriptor.param_count;
                const is_instance_method = !method.flags.contains(.static);

                if (is_instance_method or param_count > 0) {
                    // needs args
                    // TODO panic/unreachable if caller stack/args not passed, but temporarily not because main(String[] args) is not implemented
                    if (caller) |caller_stack| {
                        if (is_instance_method) {
                            // `this` param should have already been null checked
                            std.debug.assert(!caller_stack.peekAt(object.VmObjectRef.Nullable, param_count).isNull());

                            // include in count
                            param_count += 1;
                        }

                        // copy args from caller to callee local vars
                        caller_stack.transferToCallee(&local_vars, method.descriptor, is_instance_method);
                    } else {
                        std.log.warn("not passing expected args!", .{});
                    }
                }

                var dummy_return_slot: frame.Frame.StackEntry = undefined;

                const alloc = self.frameAllocator();
                var f = try alloc.create(frame.Frame);
                errdefer alloc.destroy(f);
                f.* = .{
                    .method = method,
                    .class = class.clone(),
                    .payload = .{ .java = .{
                        .operands = operands,
                        .local_vars = local_vars,
                        .code_window = code_window,
                        .dummy_return_slot = &dummy_return_slot,
                    } },
                    .parent_frame = self.top_frame,
                };

                // cant fail now, link up frame
                self.top_frame = f;

                // go go go
                interpreterLoop();
                if (state.checkException()) return null;

                return dummy_return_slot;
            },
        }
    }

    fn frameAllocator(self: @This()) std.mem.Allocator {
        return self.frames_alloc.bufs.allocator;
    }

    const PrintableCallStack = struct {
        top: ?*frame.Frame,
        exc: object.VmObjectRef.Nullable,
        pub fn format(self_: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            var top = self_.top;

            var i: u32 = 0;
            try std.fmt.formatBuf("call stack: ", options, writer);
            if (self_.exc.toStrong()) |exc|
                try std.fmt.format(
                    writer,
                    " (exception={?})",
                    .{exc},
                );

            while (top) |f| {
                try std.fmt.format(writer, "\n * {d}) {s}.{s}", .{ i, f.class.get().name, f.method.name });
                try if (f.currentPc()) |pc| std.fmt.format(writer, " (pc={d})", .{pc}) else std.fmt.formatBuf(" (native)", .{}, writer);
                top = f.parent_frame;
                i += 1;
            }

            _ = fmt;
        }
    };
    fn callstack(self: @This()) PrintableCallStack {
        return PrintableCallStack{ .top = self.top_frame, .exc = self.exception };
    }

    /// Exception reference is cloned
    pub fn setException(self: *@This(), exception: object.VmObjectRef) void {
        if (self.exception.toStrong()) |old| {
            std.log.debug("overwriting old exception {?}", .{old});
            old.drop();
        }

        self.exception = exception.clone().intoNullable();
    }

    pub fn clearException(self: *@This()) void {
        if (self.exception.toStrong()) |old| {
            std.log.debug("clearing old exception {?}", .{old});
            old.drop();
        }

        self.exception = object.VmObjectRef.Nullable.nullRef();
    }

    pub fn clearExceptionNoDrop(self: *@This()) void {
        if (self.exception.toStrong()) |old| {
            std.log.debug("clearing old exception {?}", .{old});
        }

        self.exception = object.VmObjectRef.Nullable.nullRef();
    }
};

// TODO second interpreter type that generates threaded machine code for the method e.g. `call ins1 call ins2 call ins3`
//   in generated code, local var lookup should reference the caller's stack when i<param count, to avoid copying
fn interpreterLoop() void {
    const thread = state.thread_state();
    const top_frame_ptr = @ptrToInt(thread.interpreter.top_frame);
    var ctxt_mut = insn.InsnContextMut{};
    var ctxt = insn.InsnContext{ .thread = thread, .frame = undefined, .mutable = &ctxt_mut };

    var root_reached = false;
    while (!root_reached) {
        std.log.debug("{?}", .{thread.interpreter.callstack()});

        // check for exceptions
        if (thread.interpreter.exception.toStrong()) |exc| handled: {
            if (ctxt.frame.payload == .java) {
                var java = &ctxt.frame.payload.java;
                std.log.debug("looking for exception handler for {?} at pc {} in {s}.{s}", .{ exc, ctxt.frame.currentPc().?, ctxt.frame.method.class_name, ctxt.frame.method.name });

                if (ctxt.frame.findExceptionHandler(exc, thread)) |pc| {
                    ctxt.frame.setPc(pc);
                    java.operands.clear();
                    java.operands.push(exc); // "move" out of thread interpreter
                    thread.interpreter.clearExceptionNoDrop();
                    break :handled;
                }
            }

            // unhandled exception
            std.log.debug("exception is unhandled, bubbling up", .{});
            if (thread.interpreter.top_frame) |f| {
                root_reached = @ptrToInt(f) == top_frame_ptr;
                popFrame(
                    f,
                    thread,
                );
                continue;
            } else {
                // top frame reached
                return;
            }
        }

        // code is verified to be correct, right? yeah...
        ctxt_mut.control_flow = .continue_;
        while (ctxt_mut.control_flow == .continue_) {
            // we should break out of this if an exception could have been thrown
            std.debug.assert(thread.interpreter.exception.isNull());

            // refetch on every insn, method might have changed
            const f = if (thread.interpreter.top_frame) |f| f else break;
            ctxt.frame = f;
            f.payload.java.operands.log();
            f.payload.java.local_vars.log(f.method.code.java.max_locals);

            const next_insn = f.payload.java.code_window[0];

            // lookup handler func
            const handler = insn.handler_lookup[next_insn];
            if (insn.debug_logging) std.log.debug("pc={d}: {s}", .{ ctxt.frame.currentPc().?, handler.insn_name });

            // invoke
            handler.handler(ctxt);
        }

        switch (ctxt_mut.control_flow) {
            .return_ => {
                const this_frame = thread.interpreter.top_frame.?;
                const caller_frame = this_frame.parent_frame;
                std.log.debug("returning to caller from {s}.{s}", .{ this_frame.class.get().name, this_frame.method.name });

                if (ctxt.frame.method.descriptor.isNotVoid()) {
                    const ret_value = this_frame.payload.java.operands.popRaw();
                    if (caller_frame) |caller| {
                        caller.payload.java.operands.pushRaw(ret_value);
                    } else {
                        this_frame.payload.java.dummy_return_slot.?.* = ret_value;
                    }
                }

                root_reached = @ptrToInt(this_frame) == top_frame_ptr;
                popFrame(
                    this_frame,
                    thread,
                );

                std.log.debug("{?}", .{thread.interpreter.callstack()});
                return;
            },
            .bubble_exception => {
                // threadlocal exception has been set
                std.debug.assert(!thread.interpreter.exception.isNull());

                const this_frame = thread.interpreter.top_frame.?;
                std.log.debug("bubbling exception {} to caller from {s}.{s}", .{ thread.interpreter.exception, this_frame.class.get().name, this_frame.method.name });
                root_reached = @ptrToInt(this_frame) == top_frame_ptr;
                popFrame(this_frame, thread);

                // keep looping
            },
            .check_exception => {
                // handle exception in current frame on next iteration
                std.debug.assert(!thread.interpreter.exception.isNull());
            },

            .continue_ => unreachable,
        }
    }
}

/// Disposes of top frame (f) and restores it's parent frame
fn popFrame(f: *frame.Frame, t: ?*state.ThreadEnv) void {
    const thread = t orelse state.thread_state();
    std.debug.assert(f == thread.interpreter.top_frame);

    const parent = f.parent_frame;

    // clean up this frame
    // TODO new objects are still on the stack/lvars and will be leaked...sounds like a gc is needed
    f.class.drop();
    thread.interpreter.frameAllocator().destroy(f);

    // pass execution back to caller
    thread.interpreter.top_frame = parent;
}
