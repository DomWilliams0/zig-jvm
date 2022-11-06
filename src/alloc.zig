const std = @import("std");
const state = @import("state.zig");
const Allocator = std.mem.Allocator;
const AtomicOrder = std.builtin.AtomicOrder;

/// Verbose reference counting logging
pub var logging = false;

/// Never null! Pass around `Nullable`.
pub fn VmRef(comptime T: type) type {
    // based on Rust's Arc
    return packed struct {
        const Counter = std.atomic.Atomic(u32);
        const max_counter = std.math.maxInt(u32) - 1;

        fn global_allocator() VmAllocator {
            const thread = state.thread_state();
            return thread.global.allocator;
        }

        pub const Weak = struct {
            ptr: *InnerRef,

            const dangle_ptr: *InnerRef = @intToPtr(*InnerRef, std.mem.alignBackwardGeneric(usize, std.math.maxInt(usize), @alignOf(InnerRef)));

            fn new_dangling() Weak {
                return .{ .ptr = dangle_ptr };
            }

            fn is_dangling(self: Weak) bool {
                return self.ptr == dangle_ptr;
            }

            pub fn drop(self: Weak) void {
                if (self.is_dangling()) return;

                // TODO extra debug field to track double drop
                const old = self.ptr.block.weak.fetchSub(1, .Release);
                // if (logging) std.log.debug("{}: dropped weak count to {d}", .{ self, old - 1 });

                if (old == 1) {
                    self.ptr.block.weak.fence(.Acquire);
                    // if (logging) std.log.debug("{}: dropping inner", .{self});

                    const alloc = global_allocator();
                    const alloc_size =
                        std.mem.alignForward(@sizeOf(InnerBlock), @alignOf(T)) + @sizeOf(T) + T.vmRefSize(self.ptr.get());

                    var destroy_slice = @ptrCast([*]u8, self.ptr)[0..alloc_size];
                    // if (logging) std.log.debug("{*}: freeing {*} len {d}", .{ self.ptr, destroy_slice.ptr, destroy_slice.len });
                    alloc.inner.free(destroy_slice);
                }
            }
        };

        // Strong reference (i.e. the VmRef itself)
        // pub const Strong = {
        ptr: *InnerRef,

        const Strong = @This();
        pub fn get(self: Strong) *T {
            return self.ptr.get();
        }

        pub fn clone(self: Strong) Strong {
            const old = self.ptr.block.strong.fetchAdd(1, .Monotonic);

            if (logging) std.log.debug("{}: bumped strong count to {d}", .{ self, old + 1 });

            if (old > max_counter)
                @panic("too many refs");

            return Strong{ .ptr = self.ptr };
        }

        pub fn drop(self: Strong) void {
            // TODO extra debug field to track double drop
            const old = self.ptr.block.strong.fetchSub(1, .Release);
            if (logging) std.log.debug("{}: dropped strong count to {d}", .{ self, old - 1 });
            if (old != 1) return;

            self.ptr.block.strong.fence(.Acquire);

            // destroy data
            T.vmRefDrop(self.get());

            // destroy implicit shared weak
            const implicit_weak = Weak{ .ptr = self.ptr };
            implicit_weak.drop();
        }

        pub fn cmpPtr(self: Strong, other: Strong) bool {
            return self.ptr == other.ptr;
        }

        pub fn intoNullable(self: Strong) Nullable {
            return .{ .ptr = self.ptr };
        }

        pub fn fromRaw(ptr: *InnerRef) Strong {
            return .{ .ptr = ptr };
        }

        // }; // end of Strong

        pub const NullablePtr = ?*InnerRef;

        pub const Nullable = packed struct {
            ptr: NullablePtr,

            pub fn nullRef() @This() {
                return .{ .ptr = null };
            }

            pub fn isNull(self: @This()) bool {
                return self.ptr == null;
            }

            pub fn toStrong(self: @This()) ?Strong {
                return if (self.ptr) |p| Strong{ .ptr = p } else null;
            }

            pub fn toStrongUnchecked(self: @This()) Strong {
                return Strong{ .ptr = self.ptr.? };
            }

            pub fn cmpPtr(self: Nullable, other: Nullable) bool {
                return self.ptr == other.ptr;
            }

            pub fn intoPtr(self: Nullable) NullablePtr {
                return self.ptr;
            }
            pub fn fromPtr(ptr: NullablePtr) Nullable {
                return .{ .ptr = ptr };
            }

            pub fn format(self: Nullable, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
                _ = fmt;
                if (self.toStrong()) |strong| {
                    try if (@hasDecl(T, "formatVmRef"))
                        T.formatVmRef(strong.get(), writer)
                    else
                        std.fmt.format(writer, "VmRef({s})", .{@typeName(T)});

                    return std.fmt.format(writer, "@{x}", .{@ptrToInt(strong.ptr)});
                } else return std.fmt.formatBuf("(null)", options, writer);
            }

            pub fn atomicStore(dst: *Nullable, src: Nullable, comptime order: AtomicOrder) void {
                const old: ?*InnerRef = dst.ptr;

                const src_ptr: ?*InnerRef = src.ptr;
                const dst_ptr: *?*InnerRef = &dst.ptr;
                @atomicStore(?*InnerRef, dst_ptr, src_ptr, order);

                if (Nullable.fromPtr(old).toStrong()) |p| {
                    _ = p.drop();
                }
                if (src.toStrong()) |p| {
                    _ = p.clone();
                }
            }

            /// Returns owned reference
            pub fn atomicLoad(src: *Nullable, comptime order: AtomicOrder) Nullable {
                const src_ptr: *?*InnerRef = &src.ptr;
                const local = @atomicLoad(?*InnerRef, src_ptr, order);
                const copy = Nullable{ .ptr = local };

                if (copy.toStrong()) |p| {
                    _ = p.clone();
                }
                return copy;
            }
        };

        const InnerBlock = extern struct {
            weak: Counter,
            strong: Counter,
            padding: u8, // between block and start of data
        };

        const InnerRef = extern struct {
            block: InnerBlock,
            // data: T,

            fn get(self: *InnerRef) *T {
                var byte_ptr: [*]u8 = @ptrCast([*]u8, self);
                const offset = @sizeOf(InnerBlock) + self.block.padding;
                return @ptrCast(*T, @alignCast(@alignOf(T), byte_ptr + offset));
            }
        };

        /// Size is extra size on top of base object size, must be consistent with vmRefSize.
        /// Alignment is that of the actual stored inner type, not T
        /// Returned data is undefined
        pub fn new_uninit(size: usize, comptime override_alignment: ?u29) error{OutOfMemory}!Strong {
            const alignment = override_alignment orelse @alignOf(T);
            const alloc = global_allocator();
            const padding = std.mem.alignForward(@sizeOf(InnerBlock), alignment) - @sizeOf(InnerBlock);
            const alloc_size = @sizeOf(InnerBlock) + padding + @sizeOf(T) + size;

            // TODO should be able to get cheaply zero allocated memory from OS, to avoid needing to zero it manually
            //  (which is exactly what is needed for default initialising arrays/objects)
            const buf = try alloc.inner.allocAdvanced(u8, alignment, alloc_size, .exact);
            if (logging) std.log.debug("allocated {*} len {d} with align={d}, size={d}", .{ buf.ptr, buf.len, alignment, alloc_size });
            const inner = @ptrCast(*InnerRef, buf);
            inner.* = .{
                .block = .{
                    .weak = Counter.init(1),
                    .strong = Counter.init(1),
                    .padding = @truncate(u8, padding),
                },
                // padding and data follows immediately
            };
            return Strong{ .ptr = inner };
        }

        /// Data is undefined
        pub fn new() error{OutOfMemory}!Strong {
            return new_uninit(0, null);
        }

        comptime {
            // ensure the same size as a pointer
            if (@sizeOf(VmRef(T)) != @sizeOf(*T)) @compileError("VmRef is the wrong size");
            if (@sizeOf(VmRef(T).Nullable) != @sizeOf(*T)) @compileError("VmRef is the wrong size");
            if (@sizeOf(VmRef(T).Weak) != @sizeOf(*T)) @compileError("VmRef is the wrong size");
        }

        pub fn format(self: Strong, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            return Nullable.format(self.intoNullable(), fmt, options, writer);
        }

        /// Pretty dangerous
        pub fn cast(self: Strong, comptime S: type) VmRef(S) {
            return VmRef(S){ .ptr = @ptrCast(*VmRef(S).InnerRef, self.ptr) };
        }
    };
}

/// Global instance accessed by all VmRefs (threadlocal->global, not a real global so multiple JVMs can coexist in a process)
pub const VmAllocator = struct {
    // TODO actual gc
    inner: Allocator,
};

test "vmref" {
    const VmInt = struct {
        actual_count: u16,

        const ActualInt = struct {
            elems: [150]u64,
        };

        // interface for VmRef
        fn vmRefDrop(_: *@This()) void {}
        fn vmRefSize(self: *const @This()) usize {
            return self.actual_count;
        }
    };

    const IntRef = VmRef(VmInt);

    // init global allocator
    const handle = try state.ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    // simulate runtime known size, like a class field count
    var runtime_sz: u16 = 25;
    const strong1 = try IntRef.new_uninit(runtime_sz, @alignOf(VmInt.ActualInt));
    strong1.get().* = VmInt{ .actual_count = runtime_sz };
    const strong2 = strong1.clone();

    const u32_ref = strong1.get();
    const actual_ref = @ptrCast(*VmInt.ActualInt, @alignCast(@alignOf(*VmInt.ActualInt), u32_ref));
    {
        var i = runtime_sz;
        while (i > 0) {
            actual_ref.elems[i] = 0x12341234_56785678;
            i -= 1;
        }
    }
    try std.testing.expectEqual(actual_ref.elems[7], 0x12341234_56785678);

    strong1.drop();
    strong2.drop();

    // TODO test weak

    var weak = IntRef.Weak.new_dangling();
    try std.testing.expect(weak.is_dangling());
}

test "vmref nullable ptr" {
    // std.testing.log_level = .debug;

    // init global allocator
    const handle = try state.ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    const VmDummy = struct {
        x: u64,

        // interface for VmRef
        fn vmRefDrop(_: *@This()) void {}
        fn vmRefSize(_: *const @This()) usize {
            return 0;
        }
    };

    const the_obj = try VmRef(VmDummy).new_uninit(0, @alignOf(VmDummy));
    // copied into so dont drop
    the_obj.get().x = 0;

    const copy_src = try VmRef(VmDummy).new_uninit(0, @alignOf(VmDummy));
    defer copy_src.drop();
    copy_src.get().x = 0x01234567_89abcedf;

    const null_ref = VmRef(VmDummy).Nullable.nullRef();

    try std.testing.expectEqual(the_obj.get().x, 0);

    // atomically switch the_obj to point at another
    var dst = the_obj.intoNullable();
    dst.atomicStore(copy_src.intoNullable(), .SeqCst);
    try std.testing.expectEqual(dst.toStrongUnchecked().get().x, 0x01234567_89abcedf);

    // atomically switch the_obj to null
    dst.atomicStore(null_ref, .SeqCst);
    try std.testing.expect(dst.isNull());
}
