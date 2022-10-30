const std = @import("std");
const classloader = @import("classloader.zig");
const vm_alloc = @import("alloc.zig");
const object = @import("object.zig");
const interp = @import("interpreter.zig");
const jni_sys = @import("sys/root.zig");
const string = @import("string.zig");
const JvmArgs = @import("arg.zig").JvmArgs;
const Allocator = std.mem.Allocator;

threadlocal var thread_env: ThreadEnv = undefined;
threadlocal var inited = false;

/// All threads have a reference. Owned by main thread
pub const GlobalState = struct {
    non_daemon_threads: u32,
    daemon_threads: u32,

    classloader: classloader.ClassLoader,
    allocator: vm_alloc.VmAllocator,
    args: *const JvmArgs,
    string_pool: string.StringPool,
};

/// Each thread owns one
pub const ThreadEnv = struct {
    global: *GlobalState,
    interpreter: interp.Interpreter,
    jni: *jni_sys.JniEnv,

    fn init(global: *GlobalState) ThreadEnv {
        return ThreadEnv{ .global = global };
    }

    fn deinit(self: *@This()) void {
        self.interpreter.deinit();
        self.global.allocator.inner.destroy(self.jni);
    }

    pub fn initMainThread(alloc: Allocator, args: *const JvmArgs) !JvmHandle {
        var global = try alloc.create(GlobalState);
        // TODO errdefer global.deinit();
        errdefer alloc.destroy(global);
        global.* = .{
            .non_daemon_threads = 1, // main thread
            .daemon_threads = 0,
            .classloader = try classloader.ClassLoader.new(alloc),
            .allocator = vm_alloc.VmAllocator{ .inner = alloc },
            .args = args,
            .string_pool = undefined, // set next
        };
        global.string_pool = string.StringPool.new(global);

        _ = try initThread(global);
        return .{
            .global = global,
            .main_thread = std.Thread.getCurrentId(),
        };
    }

    /// Inits threadlocal
    pub fn initThread(global: *GlobalState) !*ThreadEnv {
        if (inited) @panic("init once only");
        const jni_env = try global.allocator.inner.create(jni_sys.JniEnv);
        errdefer global.allocator.inner.destroy(jni_env);
        jni_env.* = jni_sys.api.makeEnv();

        thread_env = .{
            .global = global,
            .interpreter = try interp.Interpreter.new(global.allocator.inner),
            .jni = jni_env,
        };
        inited = true;

        return &thread_env;
    }
};

/// "Owns" the JVM main thread, created by user code
pub const JvmHandle = struct {
    global: *GlobalState,
    main_thread: std.Thread.Id,

    /// TODO optionally detach and leave daemons running, or kill everything and release all desources
    pub fn deinit(self: JvmHandle) void {
        if (self.main_thread != std.Thread.getCurrentId())
            std.debug.panic("jvm handle must be deinit'd on the main thread", .{});

        if (self.global.daemon_threads != 0 or self.global.non_daemon_threads != 1)
            std.debug.panic("TODO join threads", .{});

        thread_env.deinit();

        // all other threads should be dead now, destroy global context
        std.log.info("destroying main thread", .{});

        self.global.classloader.deinit();
        const alloc = self.global.allocator.inner;
        alloc.destroy(self.global);

        thread_env = undefined;
        inited = false;

        var self_mut = self;
        self_mut.global = undefined;
    }
};

pub fn thread_state() *ThreadEnv {
    std.debug.assert(inited);
    return &thread_env;
}

/// Terminal errors that can't be turned into exceptions
pub const ExecutionError = error{
    OutOfMemory,
    LibFfi,
};

/// Errors that should be turned into exceptions. All must have a corresponding Java class
/// defined in errorToExceptionClass (comptime checked)
pub const ExceptionError = error{
    UnsatisfiedLink,
    ClassFormat,
    NoClassDef,
    NoSuchField,
    NoSuchMethod,
    IncompatibleClassChange,
    NullPointer,
    NegativeArraySize,
    ArrayIndexOutOfBounds,
    AbstractMethod,
    Arithmetic,
    ClassCast,
};

/// Either exceptions or fatal errors
pub const Error = ExecutionError || ExceptionError;

fn errorToExceptionClass(err: Error) ?[]const u8 {
    // TODO some might not have the same constructor
    return switch (err) {
        error.UnsatisfiedLink => "java/lang/UnsatisfiedLinkError",
        error.ClassFormat => "java/lang/ClassFormatError",
        error.NoClassDef => "java/lang/NoClassDefFoundError",
        error.NoSuchField => "java/lang/NoSuchFieldError",
        error.NoSuchMethod => "java/lang/NoSuchMethodError",
        error.IncompatibleClassChange => "java/lang/IncompatibleClassChangeError",
        error.NullPointer => "java/lang/NullPointerException",
        error.NegativeArraySize => "java/lang/NegativeArraySizeException",
        error.ArrayIndexOutOfBounds => "java/lang/ArrayIndexOutOfBoundsException",
        error.AbstractMethod => "java/lang/AbstractMethodError",
        error.Arithmetic => "java/lang/ArithmeticException",
        error.ClassCast => "java/lang/ClassCastException",

        else => return null,
    };
}

comptime {
    // ensure all exception errors have defined a Java class to instantiate
    const exception_set = @typeInfo(ExceptionError).ErrorSet.?;
    inline for (exception_set) |exc| {
        const err = @field(ExceptionError, exc.name);
        if (errorToExceptionClass(err) == null) @compileError("no class defined for ExceptionError." ++ exc.name);
    }
}

/// Aborts if instantiating an error fails. TODO within here, alloc and return OutOfMemoryError and StackOverflowError
pub fn errorToException(err: Error) object.VmObjectRef {
    const S = struct {
        fn tryConvert(e: Error) ExecutionError!object.VmObjectRef {
            if (errorToExceptionClass(e)) |cls| {
                const thread = thread_state();
                const loader = if (thread.interpreter.top_frame) |f| f.class.get().loader else .bootstrap;
                const exc_class = thread.global.classloader.loadClass(cls, loader) catch |load_error| {
                    std.log.warn("failed to load exception class {s} while instantiating: {any}", .{ cls, load_error });

                    // propagate fatal errors instantiating new exception
                    // TODO ensure recursion isn't infinite
                    // TODO special case for stack overflow error
                    const new_exception = errorToException(load_error);

                    // TODO set new exception as cause
                    return new_exception;
                };
                const exc_obj = try object.VmClass.instantiateObject(exc_class);

                // TODO invoke constructor
                return exc_obj;
            } else return @errSetCast(ExecutionError, e);
        }
    };

    return S.tryConvert(err) catch |fatal| std.debug.panic("vm error: {any}", .{fatal});
}

pub fn checkException() bool {
    return !thread_state().interpreter.exception.isNull();
}
