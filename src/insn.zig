const std = @import("std");
const jvm = @import("jvm.zig");
const cafebabe = @import("cafebabe.zig");
const object = @import("object.zig");
const frame = @import("frame.zig");
const classloader = @import("classloader.zig");
const decl = @import("insn-decl.zig");

const VmClassRef = object.VmClassRef;
const VmObjectRef = object.VmObjectRef;
const Insn = decl.Insn;

const handler_fn = fn (InsnContext) void;

pub const debug_logging = true;

pub const Handler = struct {
    handler: *const handler_fn,
    insn_name: if (debug_logging) []const u8 else void,

    fn handler_wrapper(comptime insn: Insn) handler_fn {
        const S = struct {
            fn handler(ctxt: InsnContext) void {
                const name = "_" ++ insn.name;
                const func = if (@hasDecl(handlers, name)) @field(handlers, name) else nop_handler(insn);
                @call(.{ .modifier = .always_inline }, func, .{ctxt});

                ctxt.frame.code_window.? += @as(usize, insn.sz) + 1;
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
        // TODO exception
    };
};

/// Context passed to instruction handlers, preferably copied
pub const InsnContext = struct {
    const Self = @This();

    thread: *jvm.ThreadEnv,
    frame: *frame.Frame,
    mutable: *InsnContextMut,

    pub fn currentPc(self: @This()) u32 {
        const base = self.frame.method.code.code.?;
        const offset = @ptrToInt(self.frame.code_window.?) - @ptrToInt(base.ptr);
        return @truncate(u32, offset);
    }

    fn body(self: Self) [*]const u8 {
        return self.frame.code_window.?;
    }

    fn class(self: Self) *object.VmClass {
        return self.frame.class.get();
    }

    fn constantPool(self: Self) *cafebabe.ConstantPool {
        return &self.class().constant_pool;
    }

    fn readU16(self: Self) u16 {
        const b = self.body();
        return @as(u16, b[1]) << 8 | @as(u16, b[2]);
    }

    fn readU8(self: Self) u16 {
        const b = self.body();
        return b[1];
    }

    fn readI8(self: Self) i8 {
        const b = self.body();
        return @bitCast(i8, b[1]);
    }

    const ClassResolution = enum {
        resolve_only,
        ensure_initialised,
    };

    // TODO exception
    /// Returns BORROWED reference
    fn resolveClass(self: @This(), name: []const u8, comptime resolution: ClassResolution) VmClassRef {
        // resolve
        std.log.debug("resolving class {s}", .{name});
        const loaded = self.thread.global.classloader.loadClass(name, self.class().loader) catch std.debug.panic("cant load", .{});
        // TODO cache in constant pool

        switch (resolution) {
            .resolve_only => {},
            .ensure_initialised => {
                object.VmClass.ensureInitialised(loaded);
                // TODO cache initialised state in constant pool too
            },
        }

        return loaded;
    }

    fn invokeStaticMethod(self: @This(), idx: u16) void {
        // lookup method name/type/class
        const info = self.constantPool().lookupMethodOrInterfaceMethod(idx) orelse unreachable;
        if (info.is_interface) @panic("TODO interface method resolution");

        // resolve class and ensure initialised
        const class_ref = self.resolveClass(info.cls, .ensure_initialised);
        const cls = class_ref.get();

        if (cls.flags.contains(.interface)) @panic("IncompatibleClassChangeError"); // TODO

        // find method in class/superclasses/interfaces
        const method = cls.findMethodRecursive(info.name, info.ty) orelse @panic("NoSuchMethodError");

        // ensure callable
        if (!method.flags.contains(.static)) @panic("IncompatibleClassChangeError"); // TODO
        if (method.flags.contains(.abstract)) @panic("NoSuchMethodError"); // TODO
        // TODO check access control?

        // invoke with caller frame
        _ = self.thread.interpreter.executeUntilReturnWithCallerFrame(class_ref, method, self.operandStack()) catch std.debug.panic("clinit failed", .{});
    }

    fn invokeSpecialMethod(self: @This(), idx: u16) void {
        // lookup method name/type/class
        const info = self.constantPool().lookupMethodOrInterfaceMethod(idx) orelse unreachable;
        if (info.is_interface) @panic("TODO interface method resolution");

        // resolve referenced class
        const referenced_cls_ref = self.resolveClass(info.cls, .resolve_only);
        const current_supercls = self.class().super_cls;

        // decide which class to use
        // ignore ACC_SUPER
        const cls = if (!std.mem.eql(u8, info.name, "<init>") and !referenced_cls_ref.get().flags.contains(.interface) and current_supercls != null and current_supercls.?.cmpPtr(referenced_cls_ref)) //
            current_supercls.? // checked
        else
            referenced_cls_ref;

        // resolve method on this class
        const method: *const cafebabe.Method = blk: {
            const c = cls.get();

            // check self and supers
            if (c.findMethodInSelfOrSupers(info.name, info.ty)) |m| break :blk m;

            // special case for invokespecial: check Object
            if (c.flags.contains(.interface)) {
                const java_lang_Object = self.thread.global.classloader.getLoadedBootstrapClass("java/lang/Object") orelse unreachable; // TODO faster lookup
                if (java_lang_Object.get().findMethodInThisOnly(info.name, info.ty, .{ .public = true })) |m| break :blk m;
            }

            // check for maximally-specific in superinterfaces
            @panic("TODO search superinterfaces"); // and throw the right exceptions
            // break :blk null;
        }; // orelse @panic("no such method exception?");

        std.log.debug("resolved method to {s}.{s}", .{ cls.get().name, method.name });

        // invoke with caller frame
        _ = self.thread.interpreter.executeUntilReturnWithCallerFrame(cls, method, self.operandStack()) catch std.debug.panic("invokespecial failed", .{});
    }

    fn invokeVirtualMethod(self: @This(), idx: u16) void {
        // lookup method name/type/class
        const info = self.constantPool().lookupMethod(idx) orelse unreachable;

        // resolve referenced class
        const cls_ref = self.resolveClass(info.cls, .resolve_only);
        const cls = cls_ref.get();

        if (cls.flags.contains(.interface)) @panic("IncompatibleClassChangeError"); // TODO

        // find method in class/superclasses/interfaces
        const method = cls.findMethodRecursive(info.name, info.ty) orelse @panic("NoSuchMethodError");
        if (method.flags.contains(.static)) @panic("IncompatibleClassChangeError"); // TODO
        if (method.flags.contains(.abstract)) @panic("NoSuchMethodError"); // TODO
        // TODO check access control?

        // get this obj and null check
        const this_obj_ref = self.operandStack().peekAt(VmObjectRef.Nullable, method.descriptor.param_count).toStrong() orelse @panic("NPE");
        const this_obj = this_obj_ref.get();

        // select method (5.4.6)
        const this_obj_cls_ref = this_obj.class;
        const selected_method = object.VmClass.selectMethod(this_obj_cls_ref, method);
        const selected_cls = selected_method.cls.toStrong() orelse this_obj_cls_ref;
        std.debug.assert(std.mem.eql(u8, method.descriptor.str, selected_method.method.descriptor.str));

        std.log.debug("resolved method to {s}.{s}", .{ selected_cls.get().name, selected_method.method.name });

        // invoke with caller frame
        _ = self.thread.interpreter.executeUntilReturnWithCallerFrame(selected_cls, selected_method.method, self.operandStack()) catch std.debug.panic("invokevirtual failed", .{});
    }

    fn resolveField(self: @This(), idx: u16) *const cafebabe.Field {
        // lookup info
        const info = self.constantPool().lookupField(idx) orelse unreachable;

        // ensure resolved (5.4.3.2)
        // TODO cache this in constant pool

        // resolve class
        const cls = self.resolveClass(info.cls, .resolve_only);

        // lookup in class
        const field = cls.get().findFieldInSupers(info.name, info.ty, .{}) orelse @panic("NoSuchFieldError"); // TODO

        // TODO access control
        return field;
    }

    fn operandStack(self: @This()) *frame.Frame.OperandStack {
        return &self.frame.operands;
    }

    fn localVars(self: @This()) *frame.Frame.LocalVars {
        return &self.frame.local_vars;
    }

    /// If method returns not void, takes return value from top of stack
    fn returnToCaller(self: @This()) void {
        self.mutable.control_flow = .return_;
    }

    fn store(self: @This(), comptime T: type, idx: u16) void {
        const val = self.operandStack().pop(T);
        self.localVars().set(val, idx);
    }

    fn load(self: @This(), comptime T: type, idx: u16) void {
        // TODO need to bump ref count for objects?
        const val = self.localVars().get(T, idx).*;
        self.operandStack().push(val);
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
            .array => @panic("TODO putfield array"),
            .reference => @panic("TODO putfield reference"),
        };
    }

    const BinaryOp = enum { add, sub, mul, div };

    fn binaryOp(self: @This(), comptime T: type, comptime op: BinaryOp) void {
        const val2 = self.operandStack().popWiden(T);
        const val1 = self.operandStack().popWiden(T);

        const result = if (@typeInfo(T) == .Int) switch (op) {
            .add => val1 +% val2,
            .sub => val1 -% val2,
            .mul => val1 *% val2,
            .div => std.math.divTrunc(T, val1, val2) catch |err| switch (err) {
                error.Overflow => val1,
                error.DivisionByZero => @panic("ArithmeticException"),
            },
        } else if (@typeInfo(T) == .Float) switch (op) {
            .add => val1 + val2,
            .sub => val1 - val2,
            .mul => val1 * val2,
            .div => val1 / val2,
        } else @compileError("not int or float");

        std.log.debug("{} {s} {} = {}", .{ val1, switch (op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
        }, val2, result });

        self.operandStack().push(result);
    }
};

/// Instruction implementations, resolved in `handler_lookup`
pub const handlers = struct {
    pub fn _new(ctxt: InsnContext) void {
        const idx = ctxt.readU16();

        // resolve and init class
        const name = ctxt.constantPool().lookupClass(idx) orelse unreachable; // TODO infallible cp lookup for speed
        const cls = ctxt.resolveClass(name, .ensure_initialised);

        // instantiate object and push onto stack
        const obj = object.VmClass.instantiateObject(cls);

        ctxt.operandStack().push(obj);
    }

    pub fn _bipush(ctxt: InsnContext) void {
        ctxt.operandStack().push(@as(i32, ctxt.readI8()));
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

    pub fn _putstatic(ctxt: InsnContext) void {
        // TODO
        _ = ctxt;
    }

    pub fn _return(ctxt: InsnContext) void {
        ctxt.returnToCaller();
    }
    pub fn _ireturn(ctxt: InsnContext) void {
        ctxt.returnToCaller();
    }
    pub fn _lreturn(ctxt: InsnContext) void {
        ctxt.returnToCaller();
    }
    pub fn _freturn(ctxt: InsnContext) void {
        ctxt.returnToCaller();
    }
    pub fn _dreturn(ctxt: InsnContext) void {
        ctxt.returnToCaller();
    }
    pub fn _areturn(ctxt: InsnContext) void {
        ctxt.returnToCaller();
    }

    pub fn _dup(ctxt: InsnContext) void {
        var stack = ctxt.operandStack();
        stack.pushRaw(stack.peekRaw());
    }

    pub fn _invokestatic(ctxt: InsnContext) void {
        ctxt.invokeStaticMethod(ctxt.readU16());
    }
    pub fn _invokespecial(ctxt: InsnContext) void {
        ctxt.invokeSpecialMethod(ctxt.readU16());
    }
    pub fn _invokevirtual(ctxt: InsnContext) void {
        ctxt.invokeVirtualMethod(ctxt.readU16());
    }

    pub fn _putfield(ctxt: InsnContext) void {
        const field = ctxt.resolveField(ctxt.readU16());

        const val = ctxt.popPutFieldValue(field) orelse @panic("incompatible?");
        const obj_ref = ctxt.operandStack().pop(VmObjectRef.Nullable);
        const obj = obj_ref.toStrong() orelse @panic("NPE");

        switch (val.ty) {
            .int => {
                obj.get().getFieldFromField(i32, field).* = val.convertToUnchecked(i32);
            },
            .long, .float, .double, .reference => @panic("TODO"),

            .boolean,
            .byte,
            .char,
            .short,
            => unreachable, // filtered out
            .void, .returnAddress => unreachable,
        }

        std.log.debug("putfield({}, {s}) = {x}", .{ obj_ref, field.name, val });
    }

    pub fn _getfield(ctxt: InsnContext) void {
        const field = ctxt.resolveField(ctxt.readU16());
        const field_ty = field.descriptor.getType();
        _ = field_ty;

        const obj_ref = ctxt.operandStack().pop(VmObjectRef.Nullable);
        const obj = obj_ref.toStrong() orelse @panic("NPE");

        std.debug.assert(obj.get().class.get().isObject()); // verified

        const value = obj.get().getFieldFromFieldBlindly(field);
        ctxt.operandStack().pushRaw(value);
        std.log.debug("getfield({}, {s}) = {x}", .{ obj_ref, field.name, value });
    }

    pub fn _iadd(ctxt: InsnContext) void {
        ctxt.binaryOp(i32, .add);
    }
    pub fn _isub(ctxt: InsnContext) void {
        ctxt.binaryOp(i32, .sub);
    }
    pub fn _imul(ctxt: InsnContext) void {
        ctxt.binaryOp(i32, .mul);
    }
    pub fn _idiv(ctxt: InsnContext) void {
        ctxt.binaryOp(i32, .div);
    }

    pub fn _ladd(ctxt: InsnContext) void {
        ctxt.binaryOp(i64, .add);
    }
    pub fn _lsub(ctxt: InsnContext) void {
        ctxt.binaryOp(i64, .sub);
    }
    pub fn _lmul(ctxt: InsnContext) void {
        ctxt.binaryOp(i64, .mul);
    }
    pub fn _ldiv(ctxt: InsnContext) void {
        ctxt.binaryOp(i64, .div);
    }

    pub fn _fadd(ctxt: InsnContext) void {
        ctxt.binaryOp(f32, .add);
    }
    pub fn _fsub(ctxt: InsnContext) void {
        ctxt.binaryOp(f32, .sub);
    }
    pub fn _fmul(ctxt: InsnContext) void {
        ctxt.binaryOp(f32, .mul);
    }
    pub fn _fdiv(ctxt: InsnContext) void {
        ctxt.binaryOp(f32, .div);
    }

    pub fn _dadd(ctxt: InsnContext) void {
        ctxt.binaryOp(f64, .add);
    }
    pub fn _dsub(ctxt: InsnContext) void {
        ctxt.binaryOp(f64, .sub);
    }
    pub fn _dmul(ctxt: InsnContext) void {
        ctxt.binaryOp(f64, .mul);
    }
    pub fn _ddiv(ctxt: InsnContext) void {
        ctxt.binaryOp(f64, .div);
    }
};

test "sign extend" {
    const b: i8 = 16;
    try std.testing.expectEqual(@as(i32, 16), @as(i32, b));

    const c: i8 = -20;
    try std.testing.expectEqual(@as(i32, -20), @as(i32, c));
}
