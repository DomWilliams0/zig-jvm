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
    // Owned instance of current exception, don't overwrite directly
    // exception: object.VmObjectRef.Nullable,

    /// Stack of owned current exceptions. If not empty the top is the current, the second is the cause of that, etc
    exceptions: ExceptionStack(object.VmObjectRef, 16) = .{},
    /// If false, exception stack is just the cause stack, an exception is not currently active
    exception_active: bool = true,

    pub fn new(alloc: std.mem.Allocator) !Interpreter {
        return .{
            .frames_alloc = try frame.ContiguousBufferStack.new(alloc),
        };
    }

    pub fn exception(self: @This()) object.VmObjectRef.Nullable {
        if (self.exception_active) if (self.exceptions.peek()) |e| return e.intoNullable();
        return object.VmObjectRef.Nullable.nullRef();
    }

    pub fn hasException(self: @This()) bool {
        return self.exception_active and !self.exceptions.empty();
    }

    pub fn deinit(self: *@This()) void {
        self.frames_alloc.deinit();
    }

    /// Returns null if an exception was thrown and set in this thread's interpreter.
    pub fn executeUntilReturn(self: *@This(), method: *const cafebabe.Method) state.Error!?frame.Frame.StackEntry {
        return self.executeUntilReturnWithCallerFrame(method, null);
    }

    /// Returns null if an exception was thrown and set in this thread's interpreter.
    pub fn executeUntilReturnWithArgs(self: *@This(), method: *const cafebabe.Method, comptime arg_count: usize, args: [arg_count]frame.Frame.StackEntry) state.Error!?frame.Frame.StackEntry {

        // setup a fake stack to pass args
        var stack_backing = [_]frame.Frame.StackEntry{frame.Frame.StackEntry.notPresent()} ** arg_count;
        var stack = frame.Frame.OperandStack.new(&stack_backing);
        for (args) |arg| stack.pushRaw(arg);

        return self.executeUntilReturnWithCallerFrame(method, &stack);
    }

    /// Returns null if an exception was thrown and set in this thread's interpreter.
    pub fn executeUntilReturnWithCallerFrame(self: *@This(), method: *const cafebabe.Method, caller: ?*frame.Frame.OperandStack) state.Error!?frame.Frame.StackEntry {
        const class = method.class();

        std.log.debug("executing {?}", .{method});
        defer std.log.debug("finished executing {?}", .{method});

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
                    .class = class,
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
                try std.fmt.format(writer, "\n * {d}) {s} {s}", .{ i, f.method, f.method.descriptor.str });
                if (f.currentPc()) |pc| {
                    try std.fmt.format(writer, " (pc={d}", .{pc});
                    const src = f.method.lookupSource(pc);
                    try if (src.file) |src_file|
                        if (src.line) |line|
                            std.fmt.format(writer, " src={s}:{d})", .{ src_file, line })
                        else
                            std.fmt.format(writer, " src={s})", .{src_file})
                    else
                        std.fmt.format(writer, ")", .{});
                } else try std.fmt.formatBuf(" (native)", .{}, writer);
                top = f.parent_frame;
                i += 1;
            }

            _ = fmt;
        }
    };
    fn callstack(self: @This()) PrintableCallStack {
        return PrintableCallStack{ .top = self.top_frame, .exc = self.exception() };
    }

    /// Exception reference is cloned
    pub fn setException(self: *@This(), exc: object.VmObjectRef) void {
        self.exceptions.push(exc.clone());
        self.exception_active = true;
    }

    // TODO needs a variant that clears the exception stack too
    pub fn clearException(self: *@This()) void {
        self.exception_active = false;
    }

    pub fn popExceptionCauses(self: *@This(), exc_obj: object.VmObjectRef) error{ErrorBuilding}!void {
        var cause = self.exceptions.pop() orelse return;

        const method = exc_obj.get().class.get().findMethodRecursive("initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;") orelse std.debug.panic("no Throwable.initCause method on {?}", .{exc_obj});

        const StackEntry = frame.Frame.StackEntry;
        var exc = exc_obj;
        var args: [2]StackEntry = undefined;
        while (true) {
            std.log.debug("setting cause of {?} on throwable {?}", .{ cause, exc });
            args[0] = StackEntry.new(exc);
            args[1] = StackEntry.new(cause);
            _ = (self.executeUntilReturnWithArgs(method, 2, args) catch |ex| {
                std.log.warn("failed to set cause on exception {?}: {any}", .{ exc_obj, ex });
                return error.ErrorBuilding;
            }) orelse {
                // just pushed a new exception
                std.log.warn("failed to set cause on exception {?}: {?}", .{ exc_obj, self.exceptions.peek().? });
                return error.ErrorBuilding;
            };

            exc = cause;
            cause = self.exceptions.pop() orelse break;
        }
    }
};

pub fn ExceptionStack(comptime T: type, comptime N: usize) type {
    return struct {
        backing: [N]T = undefined,
        /// Next free index = N-cursor. Full when cursor=N
        cursor: u8 = 0,

        fn full(self: @This()) bool {
            return self.cursor == N;
        }

        fn empty(self: @This()) bool {
            return self.cursor == 0;
        }

        pub fn peek(self: @This()) ?T {
            return if (self.empty()) null else self.backing[N - self.cursor];
        }

        /// Order is reversed push order
        pub fn slice(self: *const @This()) []const T {
            // wtf surely this can be better
            return if (self.full()) &self.backing else if (self.empty()) &.{} else self.backing[N - self.cursor - 1 ..];
        }

        /// May discard of oldest if full
        pub fn push(self: *@This(), val: T) void {
            if (self.full()) {
                // pop earliest and shift up
                // TODO ring buffer to not need to move everything up
                var to_drop = self.backing[0];
                drop(&to_drop);
                std.mem.copyBackwards(T, self.backing[1..N], self.backing[0 .. N - 1]);

                self.backing[0] = val;
            } else {
                self.backing[N - 1 - self.cursor] = val;
                self.cursor += 1;
            }
        }

        pub fn pop(self: *@This()) ?T {
            if (self.empty()) return null;

            const val = self.backing[N - self.cursor];
            self.cursor -= 1;
            return val;
        }

        fn drop(t: *T) void {
            if (@typeInfo(T) == .Struct and @hasDecl(T, "drop"))
                t.drop();
        }
    };
}

test "exception stack" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;

    var stack = ExceptionStack(u32, 4){};

    try expect(stack.empty());
    try expect(!stack.full());

    stack.push(1);
    stack.push(2);

    try expectEqual(stack.peek().?, 2);
    try expectEqual(stack.pop().?, 2);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1 }, stack.slice());
    try expect(stack.pop().? == 1);
    try expect(stack.pop() == null);
    try expectEqual(stack.peek(), null);

    stack.push(3);
    stack.push(4);
    stack.push(5);
    stack.push(6);
    try std.testing.expectEqualSlices(u32, &.{ 6, 5, 4, 3 }, stack.slice());
    try expect(stack.full());
    stack.push(7); // discard old
    stack.push(8); // discard old
    try expect(stack.full());

    try expect(stack.pop().? == 8);
    try expect(stack.pop().? == 7);
    try expect(stack.pop().? == 6);
    try expect(stack.pop().? == 5);
    try expect(stack.pop() == null);
    try std.testing.expectEqualSlices(u32, &.{}, stack.slice());
}

// TODO second interpreter type that generates threaded machine code for the method e.g. `call ins1 call ins2 call ins3`
//   in generated code, local var lookup should reference the caller's stack when i<param count, to avoid copying
fn interpreterLoop() void {
    const thread = state.thread_state();
    const top_frame_ptr = @ptrToInt(thread.interpreter.top_frame);
    var ctxt_mut = insn.InsnContextMut{};
    var ctxt = insn.InsnContext{ .thread = thread, .frame = undefined, .mutable = &ctxt_mut };

    thread.interpreter.clearException();

    var root_reached = false;
    while (!root_reached) {
        std.log.debug("{?}", .{thread.interpreter.callstack()});

        // check for exceptions
        if (thread.interpreter.exception().toStrong()) |exc| handled: {
            if (ctxt.frame.payload == .java) {
                var java = &ctxt.frame.payload.java;
                std.log.debug("looking for exception handler for {?} at pc {} in {?}", .{ exc, ctxt.frame.currentPc().?, ctxt.frame.method });

                if (ctxt.frame.findExceptionHandler(exc, thread)) |pc| {
                    ctxt.frame.setPc(pc);
                    java.operands.clear();
                    java.operands.push(exc); // "move" out of thread interpreter

                    // pop this exception so it doesn't get assigned as its own cause
                    _ = thread.interpreter.exceptions.pop();
                    thread.interpreter.popExceptionCauses(exc) catch |e| std.debug.panic("vm error: populating exception causes on {?}: {any}", .{ exc, e });
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
            std.debug.assert(!thread.interpreter.hasException());

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
                const exc = thread.interpreter.exception().toStrongUnchecked();

                const this_frame = thread.interpreter.top_frame.?;
                std.log.debug("bubbling exception {} to caller from {s}.{s}", .{ exc, this_frame.class.get().name, this_frame.method.name });
                root_reached = @ptrToInt(this_frame) == top_frame_ptr;
                popFrame(this_frame, thread);

                // keep looping
            },
            .check_exception => {
                // handle exception in current frame on next iteration
                std.debug.assert(thread.interpreter.hasException());
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
    thread.interpreter.frameAllocator().destroy(f);

    // pass execution back to caller
    thread.interpreter.top_frame = parent;
}
