const std = @import("std");
const jvm = @import("jvm.zig");
const cafebabe = @import("cafebabe.zig");
const object = @import("object.zig");
const frame = @import("frame.zig");
const classloader = @import("classloader.zig");

const VmClassRef = object.VmClassRef;
const VmObjectRef = object.VmObjectRef;

pub const insns = [_]Insn{
    .{
        .name = "i2b",
        .id = 145,
    },
    .{
        .name = "i2c",
        .id = 146,
    },
    .{
        .name = "i2d",
        .id = 135,
    },
    .{
        .name = "l2d",
        .id = 138,
    },
    .{
        .name = "f2d",
        .id = 141,
    },
    .{
        .name = "i2f",
        .id = 134,
    },
    .{
        .name = "l2f",
        .id = 137,
    },
    .{
        .name = "d2f",
        .id = 144,
    },
    .{
        .name = "l2i",
        .id = 136,
    },
    .{
        .name = "f2i",
        .id = 139,
    },
    .{
        .name = "d2i",
        .id = 142,
    },
    .{
        .name = "i2l",
        .id = 133,
    },
    .{
        .name = "f2l",
        .id = 140,
    },
    .{
        .name = "d2l",
        .id = 143,
    },
    .{
        .name = "i2s",
        .id = 147,
    },
    // .{ .name = "tableswitch", .id = 170, .sz = 17 },
    .{
        .name = "iadd",
        .id = 96,
    },
    .{
        .name = "ladd",
        .id = 97,
    },
    .{
        .name = "fadd",
        .id = 98,
    },
    .{
        .name = "dadd",
        .id = 99,
    },
    .{
        .name = "iaload",
        .id = 46,
    },
    .{
        .name = "laload",
        .id = 47,
    },
    .{
        .name = "faload",
        .id = 48,
    },
    .{
        .name = "daload",
        .id = 49,
    },
    .{
        .name = "aaload",
        .id = 50,
    },
    .{
        .name = "baload",
        .id = 51,
    },
    .{
        .name = "caload",
        .id = 52,
    },
    .{
        .name = "saload",
        .id = 53,
    },
    .{
        .name = "iand",
        .id = 126,
    },
    .{
        .name = "land",
        .id = 127,
    },
    .{
        .name = "iastore",
        .id = 79,
    },
    .{
        .name = "lastore",
        .id = 80,
    },
    .{
        .name = "fastore",
        .id = 81,
    },
    .{
        .name = "dastore",
        .id = 82,
    },
    .{
        .name = "aastore",
        .id = 83,
    },
    .{
        .name = "bastore",
        .id = 84,
    },
    .{
        .name = "castore",
        .id = 85,
    },
    .{
        .name = "sastore",
        .id = 86,
    },
    .{
        .name = "lcmp",
        .id = 148,
    },
    .{
        .name = "fcmpl",
        .id = 149,
    },
    .{
        .name = "fcmpg",
        .id = 150,
    },
    .{
        .name = "dcmpl",
        .id = 151,
    },
    .{
        .name = "dcmpg",
        .id = 152,
    },
    .{
        .name = "dconst_0",
        .id = 14,
    },
    .{
        .name = "dconst_1",
        .id = 15,
    },
    .{
        .name = "fconst_0",
        .id = 11,
    },
    .{
        .name = "fconst_1",
        .id = 12,
    },
    .{
        .name = "fconst_2",
        .id = 13,
    },
    .{
        .name = "iconst_m1",
        .id = 2,
    },
    .{
        .name = "iconst_0",
        .id = 3,
    },
    .{
        .name = "iconst_1",
        .id = 4,
    },
    .{
        .name = "iconst_2",
        .id = 5,
    },
    .{
        .name = "iconst_3",
        .id = 6,
    },
    .{
        .name = "iconst_4",
        .id = 7,
    },
    .{
        .name = "iconst_5",
        .id = 8,
    },
    .{
        .name = "lconst_0",
        .id = 9,
    },
    .{
        .name = "lconst_1",
        .id = 10,
    },
    .{
        .name = "aconst_null",
        .id = 1,
    },
    .{ .name = "ldc", .id = 18, .sz = 1 },
    .{ .name = "ldc2_w", .id = 20, .sz = 2 },
    .{ .name = "ldc_w", .id = 19, .sz = 2 },
    .{
        .name = "idiv",
        .id = 108,
    },
    .{
        .name = "ldiv",
        .id = 109,
    },
    .{
        .name = "fdiv",
        .id = 110,
    },
    .{
        .name = "ddiv",
        .id = 111,
    },
    .{ .name = "ret", .id = 169, .sz = 1 },
    .{ .name = "getfield", .id = 180, .sz = 2 },
    .{ .name = "getstatic", .id = 178, .sz = 2 },
    .{
        .name = "return",
        .id = 177,
    },
    .{ .name = "new", .id = 187, .sz = 2 },
    .{ .name = "newarray", .id = 188, .sz = 1 },
    .{ .name = "ifeq", .id = 153, .sz = 2 },
    .{ .name = "ifne", .id = 154, .sz = 2 },
    .{ .name = "iflt", .id = 155, .sz = 2 },
    .{ .name = "ifge", .id = 156, .sz = 2 },
    .{ .name = "ifgt", .id = 157, .sz = 2 },
    .{ .name = "ifle", .id = 158, .sz = 2 },
    .{ .name = "if_acmpeq", .id = 165, .sz = 2 },
    .{ .name = "if_acmpne", .id = 166, .sz = 2 },
    .{ .name = "if_icmpeq", .id = 159, .sz = 2 },
    .{ .name = "if_icmpne", .id = 160, .sz = 2 },
    .{ .name = "if_icmplt", .id = 161, .sz = 2 },
    .{ .name = "if_icmpge", .id = 162, .sz = 2 },
    .{ .name = "if_icmpgt", .id = 163, .sz = 2 },
    .{ .name = "if_icmple", .id = 164, .sz = 2 },
    .{ .name = "ifnonnull", .id = 199, .sz = 2 },
    .{ .name = "ifnull", .id = 198, .sz = 2 },
    .{ .name = "checkcast", .id = 192, .sz = 2 },
    // .{ .name = "wide", .id = 196, .sz = 5 },
    .{ .name = "iinc", .id = 132, .sz = 2 },
    .{ .name = "bipush", .id = 16, .sz = 1 },
    .{ .name = "sipush", .id = 17, .sz = 2 },
    .{ .name = "iload", .id = 21, .sz = 1 },
    .{ .name = "lload", .id = 22, .sz = 1 },
    .{ .name = "fload", .id = 23, .sz = 1 },
    .{ .name = "dload", .id = 24, .sz = 1 },
    .{ .name = "aload", .id = 25, .sz = 1 },
    .{
        .name = "iload_0",
        .id = 26,
    },
    .{
        .name = "lload_0",
        .id = 30,
    },
    .{
        .name = "fload_0",
        .id = 34,
    },
    .{
        .name = "dload_0",
        .id = 38,
    },
    .{
        .name = "aload_0",
        .id = 42,
    },
    .{
        .name = "iload_1",
        .id = 27,
    },
    .{
        .name = "lload_1",
        .id = 31,
    },
    .{
        .name = "fload_1",
        .id = 35,
    },
    .{
        .name = "dload_1",
        .id = 39,
    },
    .{
        .name = "aload_1",
        .id = 43,
    },
    .{
        .name = "iload_2",
        .id = 28,
    },
    .{
        .name = "lload_2",
        .id = 32,
    },
    .{
        .name = "fload_2",
        .id = 36,
    },
    .{
        .name = "dload_2",
        .id = 40,
    },
    .{
        .name = "aload_2",
        .id = 44,
    },
    .{
        .name = "iload_3",
        .id = 29,
    },
    .{
        .name = "lload_3",
        .id = 33,
    },
    .{
        .name = "fload_3",
        .id = 37,
    },
    .{
        .name = "dload_3",
        .id = 41,
    },
    .{
        .name = "aload_3",
        .id = 45,
    },
    .{
        .name = "imul",
        .id = 104,
    },
    .{
        .name = "lmul",
        .id = 105,
    },
    .{
        .name = "fmul",
        .id = 106,
    },
    .{
        .name = "dmul",
        .id = 107,
    },
    .{
        .name = "ineg",
        .id = 116,
    },
    .{
        .name = "lneg",
        .id = 117,
    },
    .{
        .name = "fneg",
        .id = 118,
    },
    .{
        .name = "dneg",
        .id = 119,
    },
    .{ .name = "anewarray", .id = 189, .sz = 2 },
    .{ .name = "instanceof", .id = 193, .sz = 2 },
    .{ .name = "invokedynamic", .id = 186, .sz = 4 },
    .{ .name = "invokeinterface", .id = 185, .sz = 4 },
    .{ .name = "invokespecial", .id = 183, .sz = 2 },
    .{ .name = "invokestatic", .id = 184, .sz = 2 },
    .{ .name = "invokevirtual", .id = 182, .sz = 2 },
    .{
        .name = "monitorenter",
        .id = 194,
    },
    .{
        .name = "monitorexit",
        .id = 195,
    },
    // .{ .name = "lookupswitch", .id = 171, .sz = 13 },
    .{
        .name = "nop",
        .id = 0,
    },
    .{
        .name = "pop",
        .id = 87,
    },
    .{
        .name = "pop2",
        .id = 88,
    },
    .{
        .name = "ior",
        .id = 128,
    },
    .{
        .name = "lor",
        .id = 129,
    },
    .{ .name = "goto", .id = 167, .sz = 2 },
    .{ .name = "goto_w", .id = 200, .sz = 4 },
    .{
        .name = "irem",
        .id = 112,
    },
    .{
        .name = "lrem",
        .id = 113,
    },
    .{
        .name = "frem",
        .id = 114,
    },
    .{
        .name = "drem",
        .id = 115,
    },
    .{
        .name = "ireturn",
        .id = 172,
    },
    .{
        .name = "lreturn",
        .id = 173,
    },
    .{
        .name = "freturn",
        .id = 174,
    },
    .{
        .name = "dreturn",
        .id = 175,
    },
    .{
        .name = "areturn",
        .id = 176,
    },
    .{
        .name = "arraylength",
        .id = 190,
    },
    .{
        .name = "ishl",
        .id = 120,
    },
    .{
        .name = "lshl",
        .id = 121,
    },
    .{
        .name = "ishr",
        .id = 122,
    },
    .{
        .name = "lshr",
        .id = 123,
    },
    .{ .name = "jsr", .id = 168, .sz = 2 },
    .{ .name = "jsr_w", .id = 201, .sz = 4 },
    .{ .name = "istore", .id = 54, .sz = 1 },
    .{ .name = "lstore", .id = 55, .sz = 1 },
    .{ .name = "fstore", .id = 56, .sz = 1 },
    .{ .name = "dstore", .id = 57, .sz = 1 },
    .{ .name = "astore", .id = 58, .sz = 1 },
    .{
        .name = "istore_0",
        .id = 59,
    },
    .{
        .name = "lstore_0",
        .id = 63,
    },
    .{
        .name = "fstore_0",
        .id = 67,
    },
    .{
        .name = "dstore_0",
        .id = 71,
    },
    .{
        .name = "astore_0",
        .id = 75,
    },
    .{
        .name = "istore_1",
        .id = 60,
    },
    .{
        .name = "lstore_1",
        .id = 64,
    },
    .{
        .name = "fstore_1",
        .id = 68,
    },
    .{
        .name = "dstore_1",
        .id = 72,
    },
    .{
        .name = "astore_1",
        .id = 76,
    },
    .{
        .name = "istore_2",
        .id = 61,
    },
    .{
        .name = "lstore_2",
        .id = 65,
    },
    .{
        .name = "fstore_2",
        .id = 69,
    },
    .{
        .name = "dstore_2",
        .id = 73,
    },
    .{
        .name = "astore_2",
        .id = 77,
    },
    .{
        .name = "istore_3",
        .id = 62,
    },
    .{
        .name = "lstore_3",
        .id = 66,
    },
    .{
        .name = "fstore_3",
        .id = 70,
    },
    .{
        .name = "dstore_3",
        .id = 74,
    },
    .{
        .name = "astore_3",
        .id = 78,
    },
    .{
        .name = "isub",
        .id = 100,
    },
    .{
        .name = "lsub",
        .id = 101,
    },
    .{
        .name = "fsub",
        .id = 102,
    },
    .{
        .name = "dsub",
        .id = 103,
    },
    .{
        .name = "athrow",
        .id = 191,
    },
    .{ .name = "multianewarray", .id = 197, .sz = 3 },
    .{
        .name = "dup",
        .id = 89,
    },
    .{
        .name = "dup2",
        .id = 92,
    },
    .{
        .name = "dup2_x1",
        .id = 93,
    },
    .{
        .name = "dup2_x2",
        .id = 94,
    },
    .{
        .name = "dup_x1",
        .id = 90,
    },
    .{
        .name = "dup_x2",
        .id = 91,
    },
    .{
        .name = "iushr",
        .id = 124,
    },
    .{
        .name = "lushr",
        .id = 125,
    },
    .{ .name = "putfield", .id = 181, .sz = 2 },
    .{ .name = "putstatic", .id = 179, .sz = 2 },
    .{
        .name = "swap",
        .id = 95,
    },
    .{
        .name = "ixor",
        .id = 130,
    },
    .{
        .name = "lxor",
        .id = 131,
    },

    .{
        .name = "breakpoint",
        .id = 202,
    },
    .{
        .name = "impdep1",
        .id = 254,
    },
    .{
        .name = "impdep2",
        .id = 255,
    },
};

pub const maxInsnSize: usize = blk: {
    // also ensure no duplicates
    var seen = [_]bool{false} ** 256;
    var max_size = 0;
    for (insns) |i| {
        if (seen[i.id]) @compileError("duplicate insn");
        seen[i.id] = true;
        max_size = @maximum(max_size, i.sz);
    }

    break :blk max_size;
};

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
    for (insns) |i| {
        array[i.id] = Handler.resolve(i);
    }
    break :blk array;
};

pub const Insn = struct {
    name: []const u8,
    id: u8,
    sz: u8 = 0,
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
        self.thread.interpreter.executeUntilReturnWithCallerFrame(class_ref, method, self.operandStack()) catch std.debug.panic("clinit failed", .{});
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
        self.thread.interpreter.executeUntilReturnWithCallerFrame(cls, method, self.operandStack()) catch std.debug.panic("invokespecial failed", .{});
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

    fn loadLocalVar(self: @This(), idx: u16) void {
        const value = self.localVars().getRaw(idx).*;
        self.operandStack().pushRaw(value);
    }

    fn store(self: @This(), comptime T: type, idx: u16) void {
        _ = T; // TODO use for verification/debug checking
        const val = self.operandStack().popRaw();
        self.localVars().getRaw(idx).* = val;
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
        const val = ctxt.readU8();
        ctxt.operandStack().push(@as(i32, val));
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

    pub fn _iload_0(ctxt: InsnContext) void {
        ctxt.loadLocalVar(0);
    }
    pub fn _iload_1(ctxt: InsnContext) void {
        ctxt.loadLocalVar(1);
    }
    pub fn _iload_2(ctxt: InsnContext) void {
        ctxt.loadLocalVar(2);
    }
    pub fn _iload_3(ctxt: InsnContext) void {
        ctxt.loadLocalVar(3);
    }
};

test "sign extend" {
    const b: i8 = 16;
    try std.testing.expectEqual(@as(i32, 16), @as(i32, b));

    const c: i8 = -20;
    try std.testing.expectEqual(@as(i32, -20), @as(i32, c));
}
