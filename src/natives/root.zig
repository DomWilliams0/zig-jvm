comptime {
    // validateFunctionSignatures(@import("java_io_Console.zig"));
    // validateFunctionSignatures(@import("java_io_FileCleanable.zig"));
    // validateFunctionSignatures(@import("java_io_FileDescriptor.zig"));
    // validateFunctionSignatures(@import("java_io_FileInputStream.zig"));
    // validateFunctionSignatures(@import("java_io_FileOutputStream.zig"));
    // validateFunctionSignatures(@import("java_io_ObjectStreamClass.zig"));
    // validateFunctionSignatures(@import("java_io_RandomAccessFile.zig"));
    // validateFunctionSignatures(@import("java_io_UnixFileSystem.zig"));
    validateFunctionSignatures(@import("java_lang_Class.zig"));
    validateFunctionSignatures(@import("java_lang_ClassLoader.zig"));
    validateFunctionSignatures(@import("java_lang_Double.zig"));
    validateFunctionSignatures(@import("java_lang_Float.zig"));
    // validateFunctionSignatures(@import("java_lang_invoke_LambdaProxyClassArchive.zig"));
    // validateFunctionSignatures(@import("java_lang_invoke_MethodHandle.zig"));
    // validateFunctionSignatures(@import("java_lang_invoke_MethodHandleNatives.zig"));
    // validateFunctionSignatures(@import("java_lang_invoke_VarHandle.zig"));
    // validateFunctionSignatures(@import("java_lang_Module.zig"));
    validateFunctionSignatures(@import("java_lang_NullPointerException.zig"));
    validateFunctionSignatures(@import("java_lang_Object.zig"));
    // validateFunctionSignatures(@import("java_lang_ProcessEnvironment.zig"));
    // validateFunctionSignatures(@import("java_lang_ProcessHandleImpl.zig"));
    // validateFunctionSignatures(@import("java_lang_ProcessHandleImpl_00024Info.zig"));
    // validateFunctionSignatures(@import("java_lang_ProcessImpl.zig"));
    // validateFunctionSignatures(@import("java_lang_ref_Finalizer.zig"));
    // validateFunctionSignatures(@import("java_lang_ref_PhantomReference.zig"));
    // validateFunctionSignatures(@import("java_lang_ref_Reference.zig"));
    // validateFunctionSignatures(@import("java_lang_reflect_Array.zig"));
    // validateFunctionSignatures(@import("java_lang_reflect_Executable.zig"));
    // validateFunctionSignatures(@import("java_lang_reflect_Field.zig"));
    validateFunctionSignatures(@import("java_lang_Runtime.zig"));
    // validateFunctionSignatures(@import("java_lang_SecurityManager.zig"));
    // validateFunctionSignatures(@import("java_lang_Shutdown.zig"));
    // validateFunctionSignatures(@import("java_lang_StackStreamFactory.zig"));
    // validateFunctionSignatures(@import("java_lang_StackStreamFactory_00024AbstractStackWalker.zig"));
    // validateFunctionSignatures(@import("java_lang_StackTraceElement.zig"));
    // validateFunctionSignatures(@import("java_lang_StrictMath.zig"));
    validateFunctionSignatures(@import("java_lang_String.zig"));
    validateFunctionSignatures(@import("java_lang_StringUTF16.zig"));
    validateFunctionSignatures(@import("java_lang_System.zig"));
    validateFunctionSignatures(@import("java_lang_Thread.zig"));
    validateFunctionSignatures(@import("java_lang_Throwable.zig"));
    // validateFunctionSignatures(@import("java_net_Inet4Address.zig"));
    // validateFunctionSignatures(@import("java_net_Inet4AddressImpl.zig"));
    // validateFunctionSignatures(@import("java_net_Inet6Address.zig"));
    // validateFunctionSignatures(@import("java_net_Inet6AddressImpl.zig"));
    // validateFunctionSignatures(@import("java_net_InetAddress.zig"));
    // validateFunctionSignatures(@import("java_net_InetAddressImplFactory.zig"));
    // validateFunctionSignatures(@import("java_net_NetworkInterface.zig"));
    // validateFunctionSignatures(@import("java_nio_MappedMemoryUtils.zig"));
    validateFunctionSignatures(@import("java_security_AccessController.zig"));
    validateFunctionSignatures(@import("java_util_concurrent_atomic_AtomicLong.zig"));
    // validateFunctionSignatures(@import("java_util_TimeZone.zig"));
    // validateFunctionSignatures(@import("java_util_zip_Adler32.zig"));
    // validateFunctionSignatures(@import("java_util_zip_CRC32.zig"));
    // validateFunctionSignatures(@import("java_util_zip_Deflater.zig"));
    // validateFunctionSignatures(@import("java_util_zip_Inflater.zig"));
    // validateFunctionSignatures(@import("jdk_internal_invoke_NativeEntryPoint.zig"));
    // validateFunctionSignatures(@import("jdk_internal_jimage_NativeImageBuffer.zig"));
    // validateFunctionSignatures(@import("jdk_internal_loader_BootLoader.zig"));
    // validateFunctionSignatures(@import("jdk_internal_loader_NativeLibraries.zig"));
    validateFunctionSignatures(@import("jdk_internal_misc_CDS.zig"));
    // validateFunctionSignatures(@import("jdk_internal_misc_ScopedMemoryAccess.zig"));
    // validateFunctionSignatures(@import("jdk_internal_misc_Signal.zig"));
    validateFunctionSignatures(@import("jdk_internal_misc_Unsafe.zig"));
    validateFunctionSignatures(@import("jdk_internal_misc_VM.zig"));
    // validateFunctionSignatures(@import("jdk_internal_perf_Perf.zig"));
    // validateFunctionSignatures(@import("jdk_internal_platform_CgroupMetrics.zig"));
    // validateFunctionSignatures(@import("jdk_internal_reflect_ConstantPool.zig"));
    // validateFunctionSignatures(@import("jdk_internal_reflect_DirectConstructorHandleAccessor_00024NativeAccessor.zig"));
    // validateFunctionSignatures(@import("jdk_internal_reflect_DirectMethodHandleAccessor_00024NativeAccessor.zig"));
    // validateFunctionSignatures(@import("jdk_internal_reflect_NativeConstructorAccessorImpl.zig"));
    // validateFunctionSignatures(@import("jdk_internal_reflect_NativeMethodAccessorImpl.zig"));
    validateFunctionSignatures(@import("jdk_internal_reflect_Reflection.zig"));
    validateFunctionSignatures(@import("jdk_internal_util_SystemProps.zig"));
    // validateFunctionSignatures(@import("jdk_internal_vm_vector_VectorSupport.zig"));
    // validateFunctionSignatures(@import("jdk_internal_vm_VMSupport.zig"));
    // validateFunctionSignatures(@import("sun_net_dns_ResolverConfigurationImpl.zig"));
    // validateFunctionSignatures(@import("sun_net_PortConfig.zig"));
    // validateFunctionSignatures(@import("sun_net_sdp_SdpSupport.zig"));
    // validateFunctionSignatures(@import("sun_net_spi_DefaultProxySelector.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_DatagramChannelImpl.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_DatagramDispatcher.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_EPoll.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_EventFD.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_FileChannelImpl.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_FileDispatcherImpl.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_FileKey.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_InheritedChannel.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_IOUtil.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_NativeSocketAddress.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_NativeThread.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_Net.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_PollSelectorImpl.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_SocketDispatcher.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_UnixAsynchronousSocketChannelImpl.zig"));
    // validateFunctionSignatures(@import("sun_nio_ch_UnixDomainSockets.zig"));
    // validateFunctionSignatures(@import("sun_nio_fs_LinuxNativeDispatcher.zig"));
    // validateFunctionSignatures(@import("sun_nio_fs_LinuxWatchService.zig"));
    // validateFunctionSignatures(@import("sun_nio_fs_UnixCopyFile.zig"));
    // validateFunctionSignatures(@import("sun_nio_fs_UnixNativeDispatcher.zig"));
}

pub const JniMethod = struct {
    method: []const u8,
    desc: []const u8,
};

fn validateFunctionSignatures(comptime module: type) void {
    @setEvalBranchQuota(50000);
    const std = @import("std");
    const sys = @import("jvm").jni.sys;

    // method names and descriptors declared
    const descriptors = @field(module, "methods");

    // discovered functions
    const decls = @typeInfo(module).Struct.decls;

    // array of decls visited and declared in `methods`
    var visited: [decls.len]bool = .{false} ** decls.len;

    inline for (descriptors) |m| {
        // TODO when comptime allocators work, compute mangled native name
        const class_name = blk: {
            const name = @typeName(module);
            break :blk name[0 .. name.len - 4]; // .zig
        };
        _ = class_name;

        // lookup in decls
        const decl = for (decls) |d, i| {
            if (std.mem.eql(u8, d.name, m.method)) break .{ .idx = i, .method = @field(module, m.method) };
        } else {
            // generate a panicking stub instead
            const S = struct {
                fn panic_stub() callconv(.C) noreturn {
                    std.debug.panic("unimplemented native method {s}", .{m.method});
                }
            };

            @export(S.panic_stub, .{ .name = m.method });
            continue;
        };

        const method_info = @typeInfo(@TypeOf(decl.method));

        const expected_return_type = m.desc[std.mem.lastIndexOfScalar(u8, m.desc, ')').? + 1];
        const actual_return_type = switch (method_info.Fn.return_type.?) {
            void => 'V',
            sys.jobject, sys.jclass, sys.jstring => 'L',
            sys.jobjectArray => '[',
            sys.jboolean => 'Z',
            sys.jint => 'I',
            sys.jfloat => 'F',
            sys.jdouble => 'D',
            sys.jlong => 'J',
            else => @compileError("TODO ret type " ++ @typeName(method_info.Fn.return_type.?)),
        };

        if (actual_return_type != expected_return_type) {
            var expected: [1]u8 = .{expected_return_type};
            var actual: [1]u8 = .{actual_return_type};
            @compileError("method return type mismatch on " ++ @typeName(module) ++ "." ++ m.method ++ ": expected " ++ expected ++ " but found " ++ actual);
        }

        visited[decl.idx] = true;
    }

    // find undeclared methods
    for (decls) |d, i|
        if (std.mem.startsWith(u8, d.name, "Java_") and !visited[i])
            @compileError("native method must be declared in `methods`: " ++ @typeName(module) ++ "." ++ d.name);
}
