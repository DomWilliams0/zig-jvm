const std = @import("std");
const state = @import("state.zig");
const cafebabe = @import("cafebabe.zig");
const object = @import("object.zig");
const frame = @import("frame.zig");
const classloader = @import("classloader.zig");
const decl = @import("insn-decl.zig");

const VmClassRef = object.VmClassRef;
const VmObjectRef = object.VmObjectRef;
const Insn = decl.Insn;
const Error = state.Error;

const handler_fn = fn (InsnContext) void;

pub const debug_logging = true;

const InvokeError = Error || error{InvocationException};

pub const Handler = struct {
    handler: *const handler_fn,
    insn_name: if (debug_logging) []const u8 else void,

    fn handler_wrapper(comptime insn: Insn) handler_fn {
        const S = struct {
            fn handler(ctxt: InsnContext) void {
                const name = "_" ++ insn.name;
                const func = if (@hasDecl(handlers, name)) @field(handlers, name) else nop_handler(insn);

                const ret_type = @typeInfo(@typeInfo(@TypeOf(func)).Fn.return_type.?);
                switch (ret_type) {
                    .ErrorUnion => |err_union| {
                        if (err_union.payload != void) @compileError("unexpected return type from insn handler: " ++ @typeName(ret_type));

                        // insn that could raise an exception
                        @call(.always_inline, func, .{ctxt}) catch |err| {
                            // dont inline to avoid bloating insn handler funcs with the same exception handling code
                            @call(.never_inline, handleThrownException, .{ insn.name, ctxt, err });

                            // early return, do not increment pc
                            return;
                        };
                    },
                    .Void => {
                        // normal insn with no possible errors
                        @call(.always_inline, func, .{ctxt});
                    },
                    else => @compileError("unexpected return type from insn handler: " ++ @typeName(ret_type)),
                }

                // increment code window past this instruction
                if (!insn.jmps and insn.sz != null)
                    ctxt.frame.payload.java.code_window += @as(usize, insn.sz.?) + 1;
            }

            fn handleThrownException(comptime insn_name: []const u8, ctxt: InsnContext, err: InvokeError) void {
                switch (err) {
                    error.InvocationException => {
                        // exception has been pushed onto stack already
                        ctxt.mutable.control_flow = .check_exception;
                    },
                    else => {
                        std.log.debug("exception thrown in insn {s} handler: {any}", .{ insn_name, err });

                        // instantiate exception and throw
                        const e: Error = @errorCast(err);
                        const exc = state.errorToException(e);
                        ctxt.throwException(exc);
                    },
                }
            }
        };

        return S.handler;
    }

    fn resolve(comptime insn: Insn) Handler {
        return .{
            .handler = handler_wrapper(insn),
            .insn_name = if (debug_logging) insn.name else {},
        };
    }

    const unknown: Handler = .{
        .handler = unknown_handler,
        .insn_name = "unknown",
    };
};

fn nop_handler(comptime insn: Insn) handler_fn {
    const S = struct {
        fn nop_handler(_: InsnContext) void {
            std.debug.panic("unimplemented insn {s}", .{insn.name});
        }
    };

    return S.nop_handler;
}

fn unknown_handler(_: InsnContext) void {
    std.debug.panic("unknown instruction!!", .{});
}

pub const handler_lookup: [256]Handler = blk: {
    var array: [256]Handler = .{Handler.unknown} ** 256;
    for (decl.insns) |i| {
        array[i.id] = Handler.resolve(i);
    }
    break :blk array;
};

/// Context passed to instruction handlers that is expected to be mutated, kept
/// in a separate struct to keep the size of Insncontext smaller enough to
/// copy
pub const InsnContextMut = struct {
    control_flow: ControlFlow = .continue_,

    pub const ControlFlow = enum {
        continue_,
        return_,
        /// Exception thrown that has already been attempted to be handled in current frame,
        /// bubble up immediately
        bubble_exception,
        /// Exception was thrown that hasn't yet been attempted to be handled in current frame,
        /// don't pop top frame immediately
        check_exception,
    };
};

/// Context passed to instruction handlers, preferably copied
pub const InsnContext = struct {
    const Self = @This();

    thread: *state.ThreadEnv,
    frame: *frame.Frame,
    mutable: *InsnContextMut,

    fn body(self: Self) [*]const u8 {
        return self.frame.payload.java.code_window;
    }

    fn class(self: Self) *object.VmClass {
        return self.frame.class.get();
    }

    fn constantPool(self: Self) *cafebabe.ConstantPool {
        return &self.class().u.obj.constant_pool;
    }

    fn readU16(self: Self) u16 {
        const b = self.body();
        return @as(u16, b[1]) << 8 | @as(u16, b[2]);
    }

    fn readI16(self: Self) i16 {
        const b = self.body();
        return @as(i16, b[1]) << 8 | @as(i16, b[2]);
    }

    fn readU8(self: Self) u16 {
        const b = self.body();
        return b[1];
    }

    fn readI8(self: Self) i8 {
        const b = self.body();
        return @bitCast(b[1]);
    }

    fn readSecondI8(self: Self) i8 {
        const b = self.body();
        return @bitCast(b[2]);
    }

    fn parseI32(bytes: []const u8) i32 {
        @setRuntimeSafety(false);
        std.debug.assert(bytes.len == 4);
        return @as(i32, bytes[0]) << 24 | @as(i32, bytes[1]) << 16 | @as(i32, bytes[2]) << 8 | @as(i32, bytes[3]);
    }

    /// Offset is from the start of the instruction
    fn readI32(self: Self, offset: usize) i32 {
        const b = self.body();
        return parseI32(b[offset .. offset + 4]);
    }

    const ClassResolution = enum {
        resolve_only,
        ensure_initialised,
    };

    /// Returns BORROWED reference
    fn resolveClass(self: @This(), name: []const u8, comptime resolution: ClassResolution) Error!VmClassRef {
        return self.resolveClassWithLoader(name, resolution, self.class().loader);
    }

    /// Returns BORROWED reference
    fn resolveClassWithLoader(self: @This(), name: []const u8, comptime resolution: ClassResolution, loader: classloader.WhichLoader) Error!VmClassRef {
        // resolve
        std.log.debug("resolving class '{s}'", .{name});
        const loaded = try self.thread.global.classloader.loadClass(name, loader);
        // TODO cache in constant pool

        switch (resolution) {
            .resolve_only => {},
            .ensure_initialised => {
                try object.VmClass.ensureInitialised(loaded);
                // TODO cache initialised state in constant pool too
            },
        }

        return loaded;
    }

    // /// Returns BORROWED reference
    // fn resolvePrimitiveClass(self: @This(), name: []const u8) VmClassRef {
    //     std.log.debug("resolving primitive class {s}", .{name});
    //     const loaded = self.thread.global.classloader.loadPrimitive(name, self.class().loader) catch std.debug.panic("cant load", .{});
    //     // TODO cache in constant pool?
    //     return loaded;
    // }

    fn invokeStaticMethod(self: @This(), idx: u16) InvokeError!void {
        // lookup method name/type/class
        const info = self.constantPool().lookupMethodOrInterfaceMethod(idx) orelse unreachable;

        // resolve class and ensure initialised
        const class_ref = try self.resolveClass(info.cls, .ensure_initialised);
        const cls = class_ref.get();

        // find method in class/superclasses/interfaces
        if (info.is_interface != cls.isInterface()) return error.IncompatibleClassChange;
        const method = (if (info.is_interface)
            cls.findInterfaceMethodRecursive(info.name, info.ty)
        else
            cls.findMethodRecursive(info.name, info.ty)) orelse return error.NoSuchMethod;

        // ensure callable
        if (!method.flags.contains(.static)) return error.IncompatibleClassChange;
        if (method.flags.contains(.abstract)) return error.NoSuchMethod;
        // TODO check access control?

        // invoke with caller frame
        if ((try self.thread.interpreter.executeUntilReturnWithCallerFrame(method, self.operandStack())) == null)
            return error.InvocationException;
    }

    fn invokeSpecialMethod(self: @This(), idx: u16) InvokeError!void {
        // lookup method name/type/class
        const info = self.constantPool().lookupMethodOrInterfaceMethod(idx) orelse unreachable;
        if (info.is_interface) @panic("TODO interface method resolution");

        // resolve referenced class
        const referenced_cls_ref = try self.resolveClass(info.cls, .resolve_only);
        const current_supercls = self.class().super_cls;

        // decide which class to use
        // ignore ACC_SUPER
        const cls = if (!std.mem.eql(u8, info.name, "<init>") and !referenced_cls_ref.get().isInterface() and !current_supercls.isNull() and current_supercls.toStrongUnchecked().cmpPtr(referenced_cls_ref)) //
            current_supercls.toStrongUnchecked() // checked
        else
            referenced_cls_ref;

        // resolve method on this class
        const selected_method = blk: {
            const c = cls.get();

            // check self and supers
            if (c.findMethodInSelfOrSupers(info.name, info.ty)) |m| break :blk m;

            // special case for invokespecial: check Object
            if (c.isInterface()) {
                const java_lang_Object = self.thread.global.classloader.getLoadedBootstrapClass("java/lang/Object") orelse unreachable; // TODO faster lookup
                if (java_lang_Object.get().findMethodInThisOnly(info.name, info.ty, .{ .public = true })) |m| break :blk m;
            }

            // check for maximally-specific in superinterfaces
            @panic("TODO search superinterfaces"); // and throw the right exceptions
            // break :blk null;
        }; // orelse @panic("no such method exception?");

        // invoke with caller frame
        if ((try self.thread.interpreter.executeUntilReturnWithCallerFrame(selected_method, self.operandStack())) == null)
            return error.InvocationException;
    }

    fn invokeVirtualMethod(self: @This(), idx: u16) InvokeError!void {
        // lookup method name/type/class
        const info = self.constantPool().lookupMethod(idx) orelse unreachable;

        // resolve referenced class
        const cls_ref = try self.resolveClass(info.cls, .resolve_only);
        const cls = cls_ref.get();

        if (cls.isInterface()) return error.IncompatibleClassChange;

        // resolve referenced method
        const method = (cls.findMethodRecursive(info.name, info.ty) orelse return error.NoSuchMethod);
        std.log.debug("resolved method to {?}", .{method});
        if (method.flags.contains(.static)) return error.IncompatibleClassChange;
        // TODO check access control?

        // get this obj and null check
        const this_obj_ref = self.operandStack().peekAt(VmObjectRef.Nullable, method.descriptor.param_count).toStrong() orelse return error.NullPointer;
        const this_obj = this_obj_ref.get();
        // select method based on this_obj runtime class and resolved method (5.4.6)
        const selected_method = object.VmClass.selectMethod(this_obj.class.get(), method);
        std.debug.assert(std.mem.eql(u8, method.descriptor.str, selected_method.descriptor.str));

        std.log.debug("selected method {?}", .{selected_method});

        if (selected_method.flags.contains(.abstract)) return error.AbstractMethod;

        // invoke with caller frame
        if ((try self.thread.interpreter.executeUntilReturnWithCallerFrame(selected_method, self.operandStack())) == null)
            return error.InvocationException;
    }

    fn invokeInterfaceMethod(self: @This(), idx: u16) InvokeError!void {
        // lookup method name/type/class
        const info = self.constantPool().lookupInterfaceMethod(idx) orelse unreachable;

        // resolve referenced class
        const cls_ref = try self.resolveClass(info.cls, .resolve_only);
        const cls = cls_ref.get();

        // resolve referenced interface method
        const method = (cls.findInterfaceMethodRecursive(info.name, info.ty) orelse return error.IncompatibleClassChange);

        // get this obj and null check
        const this_obj_ref = self.operandStack().peekAt(VmObjectRef.Nullable, method.descriptor.param_count).toStrong() orelse return error.NullPointer;
        const this_obj = this_obj_ref.get();
        // select method based on this_obj runtime class and resolved method (5.4.6)
        const selected_method = object.VmClass.selectMethod(this_obj.class.get(), method);
        std.debug.assert(std.mem.eql(u8, method.descriptor.str, selected_method.descriptor.str));

        std.log.debug("resolved interface method to {?}", .{selected_method});

        if (selected_method.flags.contains(.static)) return error.IncompatibleClassChange;
        if (selected_method.flags.contains(.abstract)) return error.AbstractMethod;
        if (!selected_method.flags.contains(.public) and !selected_method.flags.contains(.private)) return error.AbstractMethod;

        // invoke with caller frame
        if ((try self.thread.interpreter.executeUntilReturnWithCallerFrame(selected_method, self.operandStack())) == null)
            return error.InvocationException;
    }

    fn resolveField(self: @This(), idx: u16, comptime variant: enum { instance, static }) Error!struct { field: *cafebabe.Field, fid: object.FieldId, cls: VmClassRef } {
        // lookup info
        const info = self.constantPool().lookupField(idx) orelse unreachable;

        // ensure resolved (5.4.3.2)
        // TODO cache this in constant pool

        // resolve and/or init class
        const cls = try self.resolveClass(info.cls, if (variant == .static) .ensure_initialised else .resolve_only);

        // lookup in class
        const field = cls.get().findFieldRecursively(info.name, info.ty, .{}) orelse return error.NoSuchField;

        // TODO access control
        return .{ .field = field.field, .fid = field.id, .cls = cls };
    }

    fn operandStack(self: @This()) *frame.Frame.OperandStack {
        return &self.frame.payload.java.operands;
    }

    fn localVars(self: @This()) *frame.Frame.LocalVars {
        return &self.frame.payload.java.local_vars;
    }

    /// If method returns not void, takes return value from top of stack
    fn returnToCaller(self: @This(), comptime T: type) void {
        self.mutable.control_flow = .return_;

        if (T == i32) {
            const ret_val = self.operandStack().peekRawPtr();
            const int_val = ret_val.convertToInt();
            if (ret_val.ty != .int) std.log.debug("converted {d} {s} return value to i32", .{ int_val, @tagName(ret_val.ty) });
            ret_val.* = frame.Frame.StackEntry.new(int_val);
        }
    }

    fn store(self: @This(), comptime T: type, idx: u16) void {
        const val = self.operandStack().pop(T);
        self.localVars().set(val, idx);
    }

    fn load(self: @This(), comptime T: type, idx: u16) void {
        // TODO need to bump ref count for objects?
        const val = if (T == i32) self.localVars().getRaw(idx).convertToInt() else self.localVars().get(T, idx);
        self.operandStack().push(val);
    }

    const ArrayStoreLoad = union(enum) {
        byte_bool,
        int: type,
        specific: type,
    };

    fn arrayStore(self: @This(), comptime opt: ArrayStoreLoad) Error!void {
        const pop_ty = switch (opt) {
            .byte_bool, .int => i32,
            .specific => |ty| ty,
        };

        const val = self.operandStack().pop(pop_ty);
        const idx_unchecked = self.operandStack().pop(i32);
        const array_opt = self.operandStack().pop(VmObjectRef.Nullable);

        const array_obj = array_opt.toStrong() orelse return error.NullPointer;
        const array = array_obj.get().getArrayHeader();

        const idx: usize = if (idx_unchecked < 0 or idx_unchecked >= array.array_len)
            return error.ArrayIndexOutOfBounds
        else
            @intCast(idx_unchecked);

        switch (opt) {
            .int => |ty| array.getElems(ty)[idx] = @intCast(val),
            .specific => |ty| array.getElems(ty)[idx] = val,
            .byte_bool => array.getElems(i8)[idx] = @intCast(val),
        }

        std.log.debug("array store {} idx {} = {}", .{ array_obj, idx, val });
    }

    fn arrayLoad(self: @This(), comptime opt: ArrayStoreLoad) Error!void {
        const pop_ty = switch (opt) {
            .byte_bool, .int => i32,
            .specific => |ty| ty,
        };
        _ = pop_ty;

        const idx_unchecked = self.operandStack().pop(i32);
        const array_opt = self.operandStack().pop(VmObjectRef.Nullable);

        const array_obj = array_opt.toStrong() orelse return error.NullPointer;
        const array = array_obj.get().getArrayHeader();

        const idx: usize = if (idx_unchecked < 0 or idx_unchecked >= array.array_len)
            return error.ArrayIndexOutOfBounds
        else
            @intCast(idx_unchecked);

        self.operandStack().push(switch (opt) {
            .int => |ty| @as(i32, @intCast(array.getElems(ty)[idx])),
            .specific => |ty| array.getElems(ty)[idx],
            .byte_bool => @as(i32, @intCast(array.getElems(i8)[idx])),
        });

        std.log.debug("array load {} idx {} = {}", .{ array_obj, idx, self.operandStack().peekRaw() });
    }

    /// Pops value from top of stack for a putfield/putstatic insn
    fn popPutFieldValue(self: @This(), field: *const cafebabe.Field) ?frame.Frame.StackEntry {
        const val = self.operandStack().popRaw();

        const expected_ty = field.descriptor.getType();

        // TODO need type checking for class and array assignment
        return switch (expected_ty) {
            .primitive => |prim| switch (prim) {
                .boolean => frame.Frame.StackEntry.new(val.convertTo(i32) & 1),
                .byte, .char, .short, .int => frame.Frame.StackEntry.new(val.convertTo(i32)),
                .float => frame.Frame.StackEntry.new(val.convertTo(f32)),
                .double => frame.Frame.StackEntry.new(val.convertTo(f64)),
                .long => frame.Frame.StackEntry.new(val.convertTo(i64)),
            },
            .array, .reference => frame.Frame.StackEntry.new(val.convertTo(object.VmObjectRef.Nullable)),
        };
    }

    const BinaryOp = enum { add, sub, mul, div, lshr, shr, shl, bit_and, bit_or, bit_xor };

    /// There is no overhead to returning and handling Error!void for binary ops that never return an error
    /// (all non .div ones)
    fn binaryOp(self: @This(), comptime T: type, comptime op: BinaryOp) Error!void {
        // special case for i64 ops, where val2 is an int instead of a long
        const val2_ty = if (T == i64 and (op == .shl or op == .shr or op == .lshr)) i32 else T;

        const val2 = self.operandStack().popWiden(val2_ty);
        const val1 = self.operandStack().popWiden(T);

        const S = struct {
            fn maskLowBits(int: i32) std.math.Log2Int(T) {
                const mask_ty = std.math.Log2Int(T);
                const mask = std.math.maxInt(mask_ty); // low 5 or 6 bits of int/long value
                const unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
                return @truncate(@as(unsigned, @intCast(int & @as(@TypeOf(int), @intCast(mask)))));
            }
        };

        const result = if (@typeInfo(T) == .Int) switch (op) {
            .add => val1 +% val2,
            .sub => val1 -% val2,
            .mul => val1 *% val2,
            .div => std.math.divTrunc(T, val1, val2) catch |err| switch (err) {
                error.Overflow => val1,
                error.DivisionByZero => return error.Arithmetic,
            },
            .shr => val1 >> S.maskLowBits(val2),
            .shl => val1 << S.maskLowBits(val2),
            .lshr => blk: {
                const x = S.maskLowBits(val2);
                break :blk if (val1 >= 0)
                    val1 >> x
                else
                    (val1 >> x) + (@as(T, 2) << ~x);
            },
            .bit_and => val1 & val2,
            .bit_or => val1 | val2,
            .bit_xor => val1 ^ val2,
        } else if (@typeInfo(T) == .Float) switch (op) {
            .add => val1 + val2,
            .sub => val1 - val2,
            .mul => val1 * val2,
            .div => val1 / val2,
            else => @compileError("unsupported float op"),
        } else @compileError("not int or float");

        std.log.debug("{} {s} {} = {}", .{ val1, switch (op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .lshr => "logical>>",
            .shr => ">>",
            .shl => "<<",
            .bit_and => "&",
            .bit_or => "|",
            .bit_xor => "^",
        }, val2, result });

        self.operandStack().push(result);
    }

    fn neg(self: @This(), comptime T: type) void {
        const value = self.operandStack().pop(T);
        const res = if (@typeInfo(T) == .Int)
            -%value
        else if (std.math.isNan(value))
            value // NaN has no sign
        else
            -value;

        self.operandStack().push(res);
    }

    fn rem(self: @This(), comptime T: type) Error!void {
        const val2 = self.operandStack().pop(T);
        const val1 = self.operandStack().pop(T);
        if (val2 == 0) return error.Arithmetic;

        const res = @rem(val1, val2);
        std.log.debug("{d} % {d} = {d}", .{ val1, val2, res });
        self.operandStack().push(res);
    }

    const BinaryCmp = enum {
        eq,
        ne,
        lt,
        ge,
        gt,
        le,

        fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            return std.fmt.formatBuf(switch (self) {
                .eq => "==",
                .ne => "!=",
                .lt => "<",
                .ge => ">=",
                .gt => ">",
                .le => "<=",
            }, options, writer);
        }
    };

    const IfCmp = enum {
        on_stack,
        zero,
    };

    fn ifCmp(self: @This(), comptime T: type, comptime op: BinaryCmp, comptime cmp: IfCmp) void {
        const val2 = switch (cmp) {
            .on_stack => self.operandStack().popWiden(T),
            .zero => 0,
        };
        const val1 = self.operandStack().popWiden(T);

        const branch = switch (op) {
            .eq => val1 == val2,
            .ne => val1 != val2,
            .lt => val1 < val2,
            .ge => val1 >= val2,
            .gt => val1 > val2,
            .le => val1 <= val2,
        };

        std.log.debug("cmp: {} {s} {} = {}{s}", .{ val1, @tagName(op), val2, branch, blk: {
            var buf: [32]u8 = undefined;
            break :blk if (branch)
                std.fmt.bufPrint(&buf, ", so jmp +{d}", .{self.readI16()}) catch unreachable
            else
                "";
        } });

        if (branch) {
            self.goto(self.readI16());
        } else {
            // manually increment pc past this insn (and size 2)
            self.goto(2 + 1);
        }
    }

    fn ifACmp(self: @This(), comptime op: BinaryCmp) void {
        const val2 = self.operandStack().pop(VmObjectRef.Nullable);
        const val1 = self.operandStack().pop(VmObjectRef.Nullable);

        const branch = switch (op) {
            .eq => val1.cmpPtr(val2),
            .ne => !val1.cmpPtr(val2),
            else => @compileError("invalid op for acmp"),
        };

        std.log.debug("acmp: {} {s} {} = {}{s}", .{ val1, @tagName(op), val2, branch, blk: {
            var buf: [32]u8 = undefined;
            break :blk if (branch)
                std.fmt.bufPrint(&buf, ", so jmp +{d}", .{self.readI16()}) catch unreachable
            else
                "";
        } });

        if (branch) {
            self.goto(self.readI16());
        } else {
            // manually increment pc past this insn (and size 2)
            self.goto(2 + 1);
        }
    }
    fn ifNull(self: @This(), comptime inverse: bool) void {
        const val = self.operandStack().pop(VmObjectRef.Nullable);
        const branch = val.isNull() != inverse;
        if (branch) {
            self.goto(self.readI16());
        } else {
            // manually increment pc past this insn (and size 2)
            self.goto(2 + 1);
        }
    }

    fn compare(self: @This(), comptime behaviour: union(enum) { nan_is_1: type, nan_is_m1: type, long }) void {
        const T = switch (behaviour) {
            .nan_is_1 => |t| t,
            .nan_is_m1 => |t| t,
            .long => i64,
        };
        const val2 = self.operandStack().pop(T);
        const val1 = self.operandStack().pop(T);

        const result: i32 = if (@typeInfo(T) == .Float and (std.math.isNan(val1) or std.math.isNan(val2)))
            switch (behaviour) {
                .nan_is_1 => 1,
                .nan_is_m1 => -1,
                else => unreachable,
            }
        else if (val1 > val2) 1 else if (val1 == val2) 0 else -1;

        self.operandStack().push(result);
    }

    /// Adds offset to pc
    fn goto(self: @This(), offset: anytype) void {
        if (offset >= 0) {
            self.frame.payload.java.code_window += @as(usize, @intCast(offset));
        } else {
            self.frame.payload.java.code_window -= @as(usize, @intCast(-offset));
        }
    }
    fn gotoAbsolute(self: @This(), pc: u32) void {
        self.frame.setPc(pc);
    }

    fn loadConstant(self: @This(), idx: u16, comptime opt: cafebabe.ConstantPool.ConstantLookupOption) Error!void {
        const constant = self.constantPool().lookupConstant(idx, opt) orelse unreachable;

        switch (constant) {
            .class => |name| {
                const cls = try self.resolveClass(name, .resolve_only);
                self.operandStack().push(cls.get().getClassInstance().clone());
            },
            .long => |val| self.operandStack().push(val),
            .double => |val| self.operandStack().push(val),
            .float => |val| self.operandStack().push(val),
            .int => |val| self.operandStack().push(val),
            .string => |val| {
                const string_ref = try self.thread.global.string_pool.getString(val);
                self.operandStack().push(string_ref);
            },
        }
    }

    fn convertPrimitive(self: @This(), comptime from: type, comptime to: type) void {
        const val = self.operandStack().pop(from);
        const from_int: ?std.builtin.Type.Int = switch (@typeInfo(from)) {
            .Int => |i| i,
            else => null,
        };
        const to_int: ?std.builtin.Type.Int = switch (@typeInfo(to)) {
            .Int => |i| i,
            else => null,
        };

        const new_val: to = if (from_int) |from_int_|
            if (to_int) |to_int_|
                if (to_int_.bits > from_int_.bits or to_int_.signedness == .unsigned) @intCast(val) else @truncate(val) // int to int
            else
                @floatFromInt(val)
        else if (to_int) |_|
            @intFromFloat(val)
        else
            @floatCast(val);

        if (from == i32) {
            if (to_int) |i| {
                if (i.bits < 32) {
                    // i2X extends back up to int again
                    const extended_val: i32 = @intCast(new_val);
                    self.operandStack().push(extended_val);
                    return;
                }
            }
        }

        self.operandStack().push(new_val);
    }

    fn throwException(self: @This(), exc: VmObjectRef) void {
        std.log.debug("throwing exception {?}", .{exc});

        // find handler in this method
        std.debug.assert(self.frame.payload == .java); // hopefully help optimiser in following function call
        if (self.frame.findExceptionHandler(exc, self.thread)) |handler| {
            self.operandStack().clear();
            self.operandStack().push(exc);
            self.gotoAbsolute(handler);
        } else {
            std.log.debug("no handler found, bubbling up {?}", .{exc});
            self.thread.interpreter.setException(exc);
            self.mutable.control_flow = .bubble_exception;
        }
    }

    fn switch_(self: @This(), comptime variant: enum { lookup, table }) void {
        const padding: u8 = blk: {
            // method code should be aligned to 4 bytes already
            std.debug.assert(std.mem.isAligned(@intFromPtr(self.frame.method.code.java.code.?.ptr), 4));

            const current = @intFromPtr(self.body());
            const pad = 3 - (current % 4);
            break :blk @truncate(pad);
        };

        const int = self.operandStack().pop(i32);
        const default = self.readI32(1 + padding);

        // i32 in classfile endianness, only converted when needed with value()
        const TableEntry = extern struct {
            bytes: [4]u8,

            fn value(e: @This()) i32 {
                return parseI32(&e.bytes);
            }
        };

        const offset = switch (variant) {
            .table => blk: {
                const lo = self.readI32(1 + padding + 4);
                const hi = self.readI32(1 + padding + 8);
                std.log.debug("tableswitch(padding={d}, default={d}, lo={d}, hi={d}, index={d})", .{ padding, default, lo, hi, int });
                std.debug.assert(lo <= hi);

                const offsets_begin_offset = 1 + padding + 12;
                const offsets_len = @sizeOf(TableEntry) * @as(usize, @intCast((hi - lo + 1)));
                const offsets = std.mem.bytesAsSlice(TableEntry, self.body()[offsets_begin_offset .. offsets_begin_offset + offsets_len]);

                break :blk if (int < lo or int > hi) default else offsets[@intCast(int - lo)].value();
            },
            .lookup => blk: {
                const npairs: usize = @intCast(self.readI32(1 + padding + 4));
                std.log.debug("lookupswitch(padding={d}, default={d}, npairs={d})", .{ padding, default, npairs });

                const MatchPair = extern struct {
                    match: TableEntry,
                    offset: TableEntry,
                };

                const pairs_begin_offset = 1 + padding + 8;
                const pairs_len = @sizeOf(MatchPair) * npairs;
                const pairs = std.mem.bytesAsSlice(MatchPair, self.body()[pairs_begin_offset .. pairs_begin_offset + pairs_len]);

                // binary search
                const key = int;
                var left: usize = 0;
                var right: usize = pairs.len;

                while (left < right) {
                    const mid = left + (right - left) / 2;
                    const pair = pairs[mid];
                    switch (std.math.order(key, pair.match.value())) {
                        .eq => break :blk pair.offset.value(),
                        .gt => left = mid + 1,
                        .lt => right = mid,
                    }
                }

                break :blk default;
            },
        };

        std.log.debug("jmping to {d}", .{offset + @as(i64, self.frame.currentPc().?)});
        self.goto(offset);
    }
};

/// Instruction implementations, resolved in `handler_lookup`
pub const handlers = struct {
    pub fn _new(ctxt: InsnContext) Error!void {
        const idx = ctxt.readU16();

        // resolve and init class
        const name = ctxt.constantPool().lookupClass(idx) orelse unreachable; // TODO infallible cp lookup for speed
        const cls = try ctxt.resolveClass(name, .ensure_initialised);

        // instantiate object and push onto stack
        const obj = try object.VmClass.instantiateObject(cls, .already_initialised);

        ctxt.operandStack().push(obj);
    }

    pub fn _bipush(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, ctxt.readI8()));
    }
    pub fn _sipush(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, ctxt.readI16()));
    }

    pub fn _iconst_m1(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, -1));
    }
    pub fn _iconst_0(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, 0));
    }
    pub fn _iconst_1(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, 1));
    }
    pub fn _iconst_2(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, 2));
    }
    pub fn _iconst_3(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, 3));
    }
    pub fn _iconst_4(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, 4));
    }
    pub fn _iconst_5(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, 5));
    }

    pub fn _lconst_0(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i64, 0));
    }
    pub fn _lconst_1(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i64, 1));
    }

    pub fn _dconst_0(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(f64, 0.0));
    }
    pub fn _dconst_1(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(f64, 1.0));
    }

    pub fn _fconst_0(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(f32, 0.0));
    }
    pub fn _fconst_1(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(f32, 1.0));
    }
    pub fn _fconst_2(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(f32, 2.0));
    }

    pub fn _iload(ctxt: InsnContext) void {
        ctxt.load(i32, ctxt.readU8());
    }
    pub fn _iload_0(ctxt: InsnContext) void {
        ctxt.load(i32, 0);
    }
    pub fn _iload_1(ctxt: InsnContext) void {
        ctxt.load(i32, 1);
    }
    pub fn _iload_2(ctxt: InsnContext) void {
        ctxt.load(i32, 2);
    }
    pub fn _iload_3(ctxt: InsnContext) void {
        ctxt.load(i32, 3);
    }

    pub fn _fload(ctxt: InsnContext) void {
        ctxt.load(f32, ctxt.readU8());
    }
    pub fn _fload_0(ctxt: InsnContext) void {
        ctxt.load(f32, 0);
    }
    pub fn _fload_1(ctxt: InsnContext) void {
        ctxt.load(f32, 1);
    }
    pub fn _fload_2(ctxt: InsnContext) void {
        ctxt.load(f32, 2);
    }
    pub fn _fload_3(ctxt: InsnContext) void {
        ctxt.load(f32, 3);
    }

    pub fn _lload(ctxt: InsnContext) void {
        ctxt.load(i64, ctxt.readU8());
    }
    pub fn _lload_0(ctxt: InsnContext) void {
        ctxt.load(i64, 0);
    }
    pub fn _lload_1(ctxt: InsnContext) void {
        ctxt.load(i64, 1);
    }
    pub fn _lload_2(ctxt: InsnContext) void {
        ctxt.load(i64, 2);
    }
    pub fn _lload_3(ctxt: InsnContext) void {
        ctxt.load(i64, 3);
    }

    pub fn _dload(ctxt: InsnContext) void {
        ctxt.load(f64, ctxt.readU8());
    }
    pub fn _dload_0(ctxt: InsnContext) void {
        ctxt.load(f64, 0);
    }
    pub fn _dload_1(ctxt: InsnContext) void {
        ctxt.load(f64, 1);
    }
    pub fn _dload_2(ctxt: InsnContext) void {
        ctxt.load(f64, 2);
    }
    pub fn _dload_3(ctxt: InsnContext) void {
        ctxt.load(f64, 3);
    }

    pub fn _aload(ctxt: InsnContext) void {
        ctxt.load(VmObjectRef.Nullable, ctxt.readU8());
    }
    pub fn _aload_0(ctxt: InsnContext) void {
        ctxt.load(VmObjectRef.Nullable, 0);
    }
    pub fn _aload_1(ctxt: InsnContext) void {
        ctxt.load(VmObjectRef.Nullable, 1);
    }
    pub fn _aload_2(ctxt: InsnContext) void {
        ctxt.load(VmObjectRef.Nullable, 2);
    }
    pub fn _aload_3(ctxt: InsnContext) void {
        ctxt.load(VmObjectRef.Nullable, 3);
    }

    pub fn _istore(ctxt: InsnContext) void {
        ctxt.store(i32, ctxt.readU8());
    }
    pub fn _istore_0(ctxt: InsnContext) void {
        ctxt.store(i32, 0);
    }
    pub fn _istore_1(ctxt: InsnContext) void {
        ctxt.store(i32, 1);
    }
    pub fn _istore_2(ctxt: InsnContext) void {
        ctxt.store(i32, 2);
    }
    pub fn _istore_3(ctxt: InsnContext) void {
        ctxt.store(i32, 3);
    }

    pub fn _fstore(ctxt: InsnContext) void {
        ctxt.store(f32, ctxt.readU8());
    }
    pub fn _fstore_0(ctxt: InsnContext) void {
        ctxt.store(f32, 0);
    }
    pub fn _fstore_1(ctxt: InsnContext) void {
        ctxt.store(f32, 1);
    }
    pub fn _fstore_2(ctxt: InsnContext) void {
        ctxt.store(f32, 2);
    }
    pub fn _fstore_3(ctxt: InsnContext) void {
        ctxt.store(f32, 3);
    }

    pub fn _lstore(ctxt: InsnContext) void {
        ctxt.store(i64, ctxt.readU8());
    }
    pub fn _lstore_0(ctxt: InsnContext) void {
        ctxt.store(i64, 0);
    }
    pub fn _lstore_1(ctxt: InsnContext) void {
        ctxt.store(i64, 1);
    }
    pub fn _lstore_2(ctxt: InsnContext) void {
        ctxt.store(i64, 2);
    }
    pub fn _lstore_3(ctxt: InsnContext) void {
        ctxt.store(i64, 3);
    }

    pub fn _dstore(ctxt: InsnContext) void {
        ctxt.store(f64, ctxt.readU8());
    }
    pub fn _dstore_0(ctxt: InsnContext) void {
        ctxt.store(f64, 0);
    }
    pub fn _dstore_1(ctxt: InsnContext) void {
        ctxt.store(f64, 1);
    }
    pub fn _dstore_2(ctxt: InsnContext) void {
        ctxt.store(f64, 2);
    }
    pub fn _dstore_3(ctxt: InsnContext) void {
        ctxt.store(f64, 3);
    }

    pub fn _astore(ctxt: InsnContext) void {
        ctxt.store(VmObjectRef.Nullable, ctxt.readU8());
    }
    pub fn _astore_0(ctxt: InsnContext) void {
        ctxt.store(VmObjectRef.Nullable, 0);
    }
    pub fn _astore_1(ctxt: InsnContext) void {
        ctxt.store(VmObjectRef.Nullable, 1);
    }
    pub fn _astore_2(ctxt: InsnContext) void {
        ctxt.store(VmObjectRef.Nullable, 2);
    }
    pub fn _astore_3(ctxt: InsnContext) void {
        ctxt.store(VmObjectRef.Nullable, 3);
    }

    pub fn _putstatic(ctxt: InsnContext) Error!void {
        const info = try ctxt.resolveField(ctxt.readU16(), .static);
        const field = info.field;
        std.log.debug("putstatic({}, {s}) {s}", .{ info.cls, field.name, field.descriptor.str });

        const val = ctxt.popPutFieldValue(field) orelse @panic("incompatible?");

        field.u.value = val.value;
        std.log.debug("putstatic({}, {s}) = {x}", .{ info.cls, field.name, val });
    }
    pub fn _getstatic(ctxt: InsnContext) Error!void {
        // resolve field and class
        const info = try ctxt.resolveField(ctxt.readU16(), .static);
        const field = info.field;

        std.debug.assert(field.flags.contains(.static)); // verified
        const raw_value = field.u.value;

        const field_ty = field.descriptor.getType();
        const ty = switch (field_ty) {
            .primitive => |prim| prim.toDataType(),
            .reference, .array => .reference,
        };

        const value = frame.Frame.StackEntry{ .value = raw_value, .ty = ty };
        ctxt.operandStack().pushRaw(value);
        std.log.debug("getstatic({}, {s}) = {x}", .{ info.cls, field.name, value });
    }

    pub fn _return(ctxt: InsnContext) void {
        ctxt.returnToCaller(void);
    }
    pub fn _ireturn(ctxt: InsnContext) void {
        ctxt.returnToCaller(i32);
    }
    pub fn _lreturn(ctxt: InsnContext) void {
        ctxt.returnToCaller(i64);
    }
    pub fn _freturn(ctxt: InsnContext) void {
        ctxt.returnToCaller(f32);
    }
    pub fn _dreturn(ctxt: InsnContext) void {
        ctxt.returnToCaller(f64);
    }
    pub fn _areturn(ctxt: InsnContext) void {
        ctxt.returnToCaller(VmObjectRef.Nullable);
    }

    pub fn _dup(ctxt: InsnContext) void {
        var stack = ctxt.operandStack();
        stack.pushRaw(stack.peekRaw());
    }
    pub fn _dup_x1(ctxt: InsnContext) void {
        var stack = ctxt.operandStack();
        const val = stack.peekRaw();
        stack.insertAt(2, val);
    }
    pub fn _dup2(ctxt: InsnContext) void {
        ctxt.operandStack().dup2();
    }

    pub fn _pop(ctxt: InsnContext) void {
        _ = ctxt.operandStack().popRaw();
    }

    pub fn _invokestatic(ctxt: InsnContext) InvokeError!void {
        return ctxt.invokeStaticMethod(ctxt.readU16());
    }
    pub fn _invokespecial(ctxt: InsnContext) InvokeError!void {
        return ctxt.invokeSpecialMethod(ctxt.readU16());
    }
    pub fn _invokevirtual(ctxt: InsnContext) InvokeError!void {
        return ctxt.invokeVirtualMethod(ctxt.readU16());
    }
    pub fn _invokeinterface(ctxt: InsnContext) InvokeError!void {
        return ctxt.invokeInterfaceMethod(ctxt.readU16());
    }

    pub fn _putfield(ctxt: InsnContext) Error!void {
        const field = try ctxt.resolveField(ctxt.readU16(), .instance);

        const val = ctxt.popPutFieldValue(field.field) orelse @panic("incompatible?");
        const obj_ref = ctxt.operandStack().pop(VmObjectRef.Nullable);
        const obj = obj_ref.toStrong() orelse return error.NullPointer;

        std.log.debug("putfield({}, {s}) = {?}", .{ obj_ref, field.field.name, val });

        const field_ty = field.field.descriptor.getType();
        switch (field_ty) {
            .primitive => |p| switch (p) {
                .int => obj.get().getField(i32, field.fid).* = val.convertToInt(),
                .byte => obj.get().getField(i8, field.fid).* = @truncate(val.convertToInt()),
                .boolean => obj.get().getField(bool, field.fid).* = val.convertToInt() != 0,
                .char => obj.get().getField(u16, field.fid).* = @intCast(val.convertToInt()),
                .short => obj.get().getField(i16, field.fid).* = @truncate(val.convertToInt()),

                .float => obj.get().getField(f32, field.fid).* = val.convertToUnchecked(f32),
                .double => obj.get().getField(f64, field.fid).* = val.convertToUnchecked(f64),
                .long => obj.get().getField(i64, field.fid).* = val.convertToUnchecked(i64),
            },
            .reference, .array => obj.get().getField(VmObjectRef.Nullable, field.fid).* = val.convertToUnchecked(VmObjectRef.Nullable),
        }
    }

    pub fn _getfield(ctxt: InsnContext) Error!void {
        const field = try ctxt.resolveField(ctxt.readU16(), .instance);
        const obj_ref = ctxt.operandStack().pop(VmObjectRef.Nullable);
        const obj = obj_ref.toStrong() orelse return error.NullPointer;

        std.log.debug("getfield({}, {s})", .{
            obj_ref,
            field.field.name,
        });
        std.debug.assert(obj.get().class.get().isObject()); // verified

        var value = obj.get().getRawField(field.field);

        // widen to int
        switch (value.ty) {
            .boolean, .byte, .char, .short => value = frame.Frame.StackEntry.new(value.convertToInt()),
            else => {},
        }

        ctxt.operandStack().pushRaw(value);
        std.log.debug("getfield({}, {s}) = {?}", .{ obj_ref, field.field.name, value });
    }

    pub fn _iadd(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .add);
    }
    pub fn _isub(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .sub);
    }
    pub fn _imul(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .mul);
    }
    pub fn _idiv(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .div);
    }
    pub fn _iushr(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .lshr);
    }
    pub fn _ishr(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .shr);
    }
    pub fn _ishl(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .shl);
    }
    pub fn _iand(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .bit_and);
    }
    pub fn _ior(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .bit_or);
    }
    pub fn _ixor(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i32, .bit_xor);
    }
    pub fn _irem(ctxt: InsnContext) Error!void {
        return ctxt.rem(i32);
    }

    pub fn _ladd(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .add);
    }
    pub fn _lsub(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .sub);
    }
    pub fn _lmul(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .mul);
    }
    pub fn _ldiv(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .div);
    }
    pub fn _lushr(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .lshr);
    }
    pub fn _lshr(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .shr);
    }
    pub fn _lshl(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .shl);
    }
    pub fn _land(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .bit_and);
    }
    pub fn _lor(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .bit_or);
    }
    pub fn _lxor(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(i64, .bit_xor);
    }
    pub fn _lrem(ctxt: InsnContext) Error!void {
        return ctxt.rem(i64);
    }

    pub fn _fadd(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f32, .add);
    }
    pub fn _fsub(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f32, .sub);
    }
    pub fn _fmul(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f32, .mul);
    }
    pub fn _fdiv(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f32, .div);
    }

    pub fn _dadd(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f64, .add);
    }
    pub fn _dsub(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f64, .sub);
    }
    pub fn _dmul(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f64, .mul);
    }
    pub fn _ddiv(ctxt: InsnContext) Error!void {
        return ctxt.binaryOp(f64, .div);
    }

    pub fn _ldc(ctxt: InsnContext) Error!void {
        try ctxt.loadConstant(ctxt.readU8(), .any_single);
    }
    pub fn _ldc_w(ctxt: InsnContext) Error!void {
        try ctxt.loadConstant(ctxt.readU16(), .any_single);
    }
    pub fn _ldc2_w(ctxt: InsnContext) Error!void {
        try ctxt.loadConstant(ctxt.readU16(), .long_double);
    }

    pub fn _newarray(ctxt: InsnContext) Error!void {
        const elem_ty = switch (ctxt.readU8()) {
            4 => "[Z",
            5 => "[C",
            6 => "[F",
            7 => "[D",
            8 => "[B",
            9 => "[S",
            10 => "[I",
            11 => "[J",
            else => unreachable,
        };

        const count = ctxt.operandStack().pop(i32);
        if (count < 0) return error.NegativeArraySize;

        const array_cls = try ctxt.resolveClassWithLoader(elem_ty, .resolve_only, .bootstrap);

        const array = try object.VmClass.instantiateArray(array_cls, @intCast(count));
        ctxt.operandStack().push(array);
    }

    pub fn _anewarray(ctxt: InsnContext) Error!void {
        const elem_cls_name = ctxt.constantPool().lookupClass(ctxt.readU16()) orelse unreachable;
        const elem_cls = try ctxt.resolveClass(elem_cls_name, .resolve_only);
        _ = elem_cls;

        const count = ctxt.operandStack().pop(i32);
        if (count < 0) return error.NegativeArraySize;

        const array_cls = try ctxt.thread.global.classloader.loadClassAsArrayElement(elem_cls_name, ctxt.class().loader);

        const array = try object.VmClass.instantiateArray(array_cls, @intCast(count));
        ctxt.operandStack().push(array);
    }

    pub fn _iastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .int = i32 });
    }
    pub fn _sastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .int = i16 });
    }
    pub fn _bastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.byte_bool);
    }
    pub fn _castore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .int = u16 });
    }
    pub fn _fastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .specific = f32 });
    }
    pub fn _dastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .specific = f64 });
    }
    pub fn _lastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .specific = i64 });
    }
    pub fn _aastore(ctxt: InsnContext) Error!void {
        return ctxt.arrayStore(.{ .specific = VmObjectRef.Nullable });
    }
    pub fn _iaload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .int = i32 });
    }
    pub fn _saload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .int = i16 });
    }
    pub fn _baload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.byte_bool);
    }
    pub fn _caload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .int = u16 });
    }
    pub fn _faload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .specific = f32 });
    }
    pub fn _daload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .specific = f64 });
    }
    pub fn _laload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .specific = i64 });
    }
    pub fn _aaload(ctxt: InsnContext) Error!void {
        return ctxt.arrayLoad(.{ .specific = VmObjectRef.Nullable });
    }

    pub fn _arraylength(ctxt: InsnContext) Error!void {
        const array_opt = ctxt.operandStack().pop(VmObjectRef.Nullable);
        const array_obj = array_opt.toStrong() orelse return error.NullPointer;
        const len = array_obj.get().getArrayHeader().array_len;
        ctxt.operandStack().push(@as(i32, @intCast(len)));
    }

    pub fn _ifeq(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .eq, .zero);
    }
    pub fn _ifne(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .ne, .zero);
    }
    pub fn _iflt(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .lt, .zero);
    }
    pub fn _ifge(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .ge, .zero);
    }
    pub fn _ifgt(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .gt, .zero);
    }
    pub fn _ifle(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .le, .zero);
    }

    pub fn _if_icmpeq(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .eq, .on_stack);
    }
    pub fn _if_icmpne(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .ne, .on_stack);
    }
    pub fn _if_icmplt(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .lt, .on_stack);
    }
    pub fn _if_icmpge(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .ge, .on_stack);
    }
    pub fn _if_icmpgt(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .gt, .on_stack);
    }
    pub fn _if_icmple(ctxt: InsnContext) void {
        ctxt.ifCmp(i32, .le, .on_stack);
    }

    pub fn _ifnull(ctxt: InsnContext) void {
        ctxt.ifNull(false);
    }
    pub fn _ifnonnull(ctxt: InsnContext) void {
        ctxt.ifNull(true);
    }

    pub fn _if_acmpeq(ctxt: InsnContext) void {
        ctxt.ifACmp(.eq);
    }
    pub fn _if_acmpne(ctxt: InsnContext) void {
        ctxt.ifACmp(.ne);
    }
    pub fn _fcmpg(ctxt: InsnContext) void {
        ctxt.compare(.{ .nan_is_1 = f32 });
    }
    pub fn _fcmpl(ctxt: InsnContext) void {
        ctxt.compare(.{ .nan_is_m1 = f32 });
    }
    pub fn _dcmpg(ctxt: InsnContext) void {
        ctxt.compare(.{ .nan_is_1 = f64 });
    }
    pub fn _dcmpl(ctxt: InsnContext) void {
        ctxt.compare(.{ .nan_is_m1 = f64 });
    }
    pub fn _lcmp(ctxt: InsnContext) void {
        ctxt.compare(.long);
    }

    pub fn _iinc(ctxt: InsnContext) void {
        const lvar = ctxt.localVars().getPtr(i32, ctxt.readU8());
        const offset: i32 = @intCast(ctxt.readSecondI8());
        std.log.debug("increment {} += {}", .{ lvar.*, offset });
        lvar.* += offset;
    }

    pub fn _goto(ctxt: InsnContext) void {
        const offset = ctxt.readI16();
        const pc = ctxt.frame.currentPc().?;
        std.log.debug("goto {}", .{@as(i33, pc) +% @as(i33, @intCast(offset))});
        ctxt.goto(offset);
    }

    pub fn _i2b(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i32, i8);
    }
    pub fn _i2c(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i32, u16);
    }
    pub fn _i2d(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i32, f64);
    }
    pub fn _i2f(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i32, f32);
    }
    pub fn _i2l(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i32, i64);
    }
    pub fn _i2s(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i32, i16);
    }

    pub fn _d2f(ctxt: InsnContext) void {
        ctxt.convertPrimitive(f64, f32);
    }
    pub fn _d2i(ctxt: InsnContext) void {
        ctxt.convertPrimitive(f64, i32);
    }
    pub fn _d2l(ctxt: InsnContext) void {
        ctxt.convertPrimitive(f64, i64);
    }

    pub fn _f2d(ctxt: InsnContext) void {
        ctxt.convertPrimitive(f32, f64);
    }
    pub fn _f2i(ctxt: InsnContext) void {
        ctxt.convertPrimitive(f32, i32);
    }
    pub fn _f2l(ctxt: InsnContext) void {
        ctxt.convertPrimitive(f32, i64);
    }

    pub fn _l2f(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i64, f32);
    }
    pub fn _l2d(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i64, f64);
    }
    pub fn _l2i(ctxt: InsnContext) void {
        ctxt.convertPrimitive(i64, i32);
    }
    pub fn _ineg(ctxt: InsnContext) void {
        ctxt.neg(i32);
    }
    pub fn _lneg(ctxt: InsnContext) void {
        ctxt.neg(i64);
    }
    pub fn _fneg(ctxt: InsnContext) void {
        ctxt.neg(f32);
    }
    pub fn _dneg(ctxt: InsnContext) void {
        ctxt.neg(f64);
    }

    pub fn _aconst_null(ctxt: InsnContext) void {
        ctxt.operandStack().push(VmObjectRef.Nullable.nullRef());
    }

    pub fn _athrow(ctxt: InsnContext) Error!void {
        const exc = if (ctxt.operandStack().pop(VmObjectRef.Nullable).toStrong()) |exc|
            exc
        else blk: {
            std.log.debug("trying to throw null, instantiating NPE", .{});

            const npe_cls = try ctxt.resolveClassWithLoader("java/lang/NullPointerException", .ensure_initialised, .bootstrap);
            const npe = try object.VmClass.instantiateObject(npe_cls, .already_initialised);
            break :blk npe;
        };

        ctxt.throwException(exc);
    }
    pub fn _monitorenter(ctxt: InsnContext) Error!void {
        const obj = ctxt.operandStack().pop(VmObjectRef.Nullable).toStrong() orelse return error.NullPointer;
        std.log.warn("monitorenter {?} not implemented", .{obj});
    }
    pub fn _monitorexit(ctxt: InsnContext) Error!void {
        const obj = ctxt.operandStack().pop(VmObjectRef.Nullable).toStrong() orelse return error.NullPointer;
        std.log.warn("monitorexit {?} not implemented", .{obj});
    }

    pub fn _instanceof(ctxt: InsnContext) Error!void {
        const obj = ctxt.operandStack().pop(VmObjectRef.Nullable).toStrong() orelse {
            ctxt.operandStack().push(@as(i32, 0));
            return;
        };

        const cls_name = ctxt.constantPool().lookupClass(ctxt.readU16()) orelse unreachable;
        const cls = try ctxt.resolveClass(cls_name, .resolve_only);
        const result = object.VmClass.isInstanceOf(obj.get().class, cls);
        std.log.debug("isinstanceof({?}, {s}) = {any}", .{ obj, cls.get().name, result });
        ctxt.operandStack().push(@as(i32, @intFromBool(result)));
    }
    pub fn _checkcast(ctxt: InsnContext) Error!void {
        const obj = ctxt.operandStack().peekAt(VmObjectRef.Nullable, 0).toStrong() orelse return;

        const cls_name = ctxt.constantPool().lookupClass(ctxt.readU16()) orelse unreachable;
        const cls = try ctxt.resolveClass(cls_name, .resolve_only);
        const result = object.VmClass.isInstanceOf(obj.get().class, cls);
        std.log.debug("checkcast({?}, {s}) = {any}", .{ obj, cls.get().name, result });
        if (!result)
            return error.ClassCast;
    }
    pub fn _lookupswitch(ctxt: InsnContext) void {
        ctxt.switch_(.lookup);
    }
    pub fn _tableswitch(ctxt: InsnContext) void {
        ctxt.switch_(.table);
    }
};

test "sign extend" {
    const b: i8 = 16;
    try std.testing.expectEqual(@as(i32, 16), @as(i32, b));

    const c: i8 = -20;
    try std.testing.expectEqual(@as(i32, -20), @as(i32, c));
}
