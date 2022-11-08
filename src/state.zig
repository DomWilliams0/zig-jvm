const std = @import("std");
const classloader = @import("classloader.zig");
const vm_alloc = @import("alloc.zig");
const object = @import("object.zig");
const interp = @import("interpreter.zig");
const jni_sys = @import("sys/root.zig");
const string = @import("string.zig");
const call = @import("call.zig");
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
    hashcode_rng: std.rand.DefaultPrng,

    /// Null until Object and Class are loaded
    main_thread: object.VmObjectRef.Nullable,
    /// Null until Object and Class are loaded
    main_thread_group: object.VmObjectRef.Nullable,

    pub fn postBootstrapInit(self: *@This()) Error!void {
        // init strings
        self.string_pool.postBootstrapInit();

        // init threads
        const t = thread_state();
        const java_lang_ThreadGroup = self.classloader.getLoadedBootstrapClass("java/lang/ThreadGroup") orelse @panic("no java/lang/ThreadGroup");
        const java_lang_Thread = self.classloader.getLoadedBootstrapClass("java/lang/Thread") orelse @panic("no java/lang/Thread");
        const java_lang_Object = self.classloader.getLoadedBootstrapClass("java/lang/Object") orelse unreachable;

        const thread_group = try object.VmClass.instantiateObject(java_lang_ThreadGroup);
        _ = try call.runMethod(t, java_lang_ThreadGroup, "<init>", "()V", .{thread_group});

        const thread_name = try self.string_pool.getString("MainThread");
        _ = thread_name;

        const thread = try object.VmClass.instantiateObject(java_lang_Thread);
        // can't run Thread constructor yet because it calls currentThread()
        _ = try call.runMethod(t, java_lang_Object, "<init>", "()V", .{thread});
        call.setFieldInfallible(thread, "daemon", "Z", false);
        const prio = call.getStaticFieldInfallible(java_lang_Thread, "NORM_PRIORITY", i32);
        call.setFieldInfallible(thread, "priority", "I", prio);
        call.setFieldInfallible(thread, "threadStatus", "I", @as(i32, 1));
        call.setFieldInfallible(thread, "group", "Ljava/lang/ThreadGroup;", thread_group.clone());

        self.main_thread = thread.intoNullable();
        self.main_thread_group = thread_group.intoNullable();

        // init main thread's Thread object now
        thread_state().thread_obj = thread.clone();
    }
};

/// Each thread owns one
pub const ThreadEnv = struct {
    global: *GlobalState,
    interpreter: interp.Interpreter,
    jni: *jni_sys.JniEnv,
    /// java.lang.Thread instance
    thread_obj: object.VmObjectRef,

    /// String allocated in global allocator passed to next exception constructor
    error_context: ?[]const u8 = null,

    // fn init(global: *GlobalState) ThreadEnv {
    //     return ThreadEnv{ .global = global, };
    // }

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
            .hashcode_rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())),
            .string_pool = undefined, // set next
            .main_thread = object.VmObjectRef.Nullable.nullRef(),
            .main_thread_group = object.VmObjectRef.Nullable.nullRef(),
        };
        global.string_pool = string.StringPool.new(global);

        // thread instance will be set later in bootstrap
        _ = try initThread(global, undefined);
        return .{
            .global = global,
            .main_thread = std.Thread.getCurrentId(),
        };
    }

    /// Inits threadlocal. Thread is owned instance
    pub fn initThread(global: *GlobalState, thread: object.VmObjectRef) !*ThreadEnv {
        if (inited) @panic("init once only");
        const jni_env = try global.allocator.inner.create(jni_sys.JniEnv);
        errdefer global.allocator.inner.destroy(jni_env);
        jni_env.* = jni_sys.api.makeEnv();

        thread_env = .{
            .global = global,
            .interpreter = try interp.Interpreter.new(global.allocator.inner),
            .jni = jni_env,
            .thread_obj = thread,
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
    /// Instantiating and setting causes on Java exceptions/errors
    ErrorBuilding,
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
    ArrayStore,
    AbstractMethod,
    Arithmetic,
    ClassCast,
    ClassNotFound,
    IndexOutOfBounds,
    IllegalArgument,
    Internal,
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
        error.ArrayStore => "java/lang/ArrayStoreException",
        error.AbstractMethod => "java/lang/AbstractMethodError",
        error.Arithmetic => "java/lang/ArithmeticException",
        error.ClassCast => "java/lang/ClassCastException",
        error.ClassNotFound => "java/lang/ClassNotFoundException",
        error.IndexOutOfBounds => "java/lang/IndexOutOfBoundsException",
        error.IllegalArgument => "java/lang/IllegalArgumentException",
        error.Internal => "java/lang/InternalError",

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

pub const MethodDescription = struct { cls: []const u8, method: []const u8, desc: []const u8 };

// TODO ensure that theres no infinite recursion if e.g. NoClassDefError cannot be loaded
pub fn makeError(e: Error, ctxt: anytype) Error {
    const ArgsType = @TypeOf(ctxt);

    const helper = struct {
        fn format(
            data: ArgsType,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            _ = fmt;

            const ArgsInfo = @typeInfo(ArgsType);
            if (ArgsInfo == .Pointer) {
                const child = @typeInfo(ArgsInfo.Pointer.child);
                if (child == .Array) {
                    if (child.Array.child == u8) {
                        // comptime string! bloody hell
                        return try std.fmt.format(writer, "{s}", .{data});
                    }
                }
            }

            switch (ArgsType) {
                *const @import("cafebabe.zig").Method, object.VmClassRef, object.VmClassRef.Nullable => try std.fmt.format(writer, "{?}", .{data}),
                []const u8, [:0]const u8 => try std.fmt.format(writer, "{s}", .{data}),
                MethodDescription => try std.fmt.format(writer, "{s}.{s}", .{ data.cls, data.method }),
                else => @compileError("unexpected type " ++ @typeName(ArgsType)),
            }
        }
    };

    const t = thread_state();
    const alloc = t.global.allocator.inner;

    const s = std.fmt.allocPrint(alloc, "{?}", .{std.fmt.Formatter(helper.format){ .data = ctxt }}) catch |err| {
        switch (err) {
            error.OutOfMemory => {
                std.log.err("out of memory allocating context for {any}", .{err});
                return err;
            },
        }
    };

    if (t.error_context) |old| {
        std.log.warn("overwriting error context without consuming it: {s}", .{old});
        alloc.free(old);
    }

    t.error_context = s;
    return e;
}

/// Aborts if instantiating an error fails. TODO within here, alloc and return OutOfMemoryError and StackOverflowError
pub fn errorToException(err: Error) object.VmObjectRef {
    const S = struct {
        const Recurse = enum {
            yes,
            no,

            fn fail(comptime self: @This(), e: Error) ExecutionError!object.VmObjectRef {
                return if (self == .yes) tryConvert(.no, e) else error.ErrorBuilding;
            }
        };

        fn tryConvert(comptime recurse: Recurse, e: Error) ExecutionError!object.VmObjectRef {
            if (errorToExceptionClass(e)) |cls| {
                const thread = thread_state();
                const loader = if (thread.interpreter.top_frame) |f| f.class.get().loader else .bootstrap;
                const exc_class = thread.global.classloader.loadClass(cls, loader) catch |load_error| {
                    std.log.warn("failed to load exception class {s} while instantiating: {any}", .{ cls, load_error });
                    return recurse.fail(load_error);
                };
                const exc_obj = try object.VmClass.instantiateObject(exc_class);

                // invoke constructor
                var run_default_constructor = true;
                if (thread.error_context) |ctxt| {
                    // we have an extra detail string to pass to throwable constructor

                    defer {
                        // consume context regardless of success
                        thread.error_context = null;
                        thread.global.allocator.inner.free(ctxt);
                    }

                    // if no detail constructor exists, run default and ignore the context
                    const success = execDetailConstructor(thread, exc_class, exc_obj, ctxt) catch |constructor_error| return recurse.fail(constructor_error);
                    run_default_constructor = !success;
                }

                if (run_default_constructor) {
                    execDefaultConstructor(thread, exc_class, exc_obj) catch |constructor_error| return recurse.fail(constructor_error);
                }

                // recursively set causes
                try thread.interpreter.popExceptionCauses(exc_obj);

                return exc_obj;
            } else return @errSetCast(ExecutionError, e);
        }

        fn execDetailConstructor(thread: *ThreadEnv, exc_class: object.VmClassRef, exc_obj: object.VmObjectRef, ctxt: []const u8) Error!bool {
            const ctxt_str = try thread.global.string_pool.getString(ctxt);

            _ = call.runMethod(thread, exc_class, "<init>", "(Ljava/lang/String;)V", .{ exc_obj, ctxt_str }) catch |e| switch (e) {
                error.NoClassDef => return false, // no constructor, oh well
                else => return e,
            };

            return true;
        }

        fn execDefaultConstructor(thread: *ThreadEnv, exc_class: object.VmClassRef, exc_obj: object.VmObjectRef) Error!void {
            _ = try call.runMethod(thread, exc_class, "<init>", "()V", .{exc_obj});
        }
    };

    return S.tryConvert(.yes, err) catch |fatal| std.debug.panic("vm error: {any}", .{fatal});
}

pub fn checkException() bool {
    return thread_state().interpreter.hasException();
}
