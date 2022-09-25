const std = @import("std");
const object = @import("object.zig");
const jvm = @import("jvm.zig");
const Allocator = std.mem.Allocator;

/// Verbose reference counting logging
var logging = false;

pub fn VmRef(comptime T: type) type {
    // based on Rust's Arc
    return struct {
        const Counter = std.atomic.Atomic(u32);
        const max_counter = std.math.maxInt(u32) - 1;

        fn global_allocator() VmAllocator {
            const thread = jvm.thread_state();
            return thread.global.allocator;
        }

        pub const Weak = struct {
            ptr: *Inner,

            const dangle_ptr: *Inner = @intToPtr(*Inner, std.mem.alignBackwardGeneric(usize, std.math.maxInt(usize), @alignOf(Inner)));

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
                if (logging) std.log.debug("{*}: dropped weak count to {d}", .{ self.ptr, old - 1 });

                if (old == 1) {
                    self.ptr.block.weak.fence(.Acquire);
                    if (logging) std.log.debug("{*}: dropping inner", .{self.ptr});

                    const alloc = global_allocator();
                    const alloc_size = @sizeOf(InnerBlock) + T.vmRefSize(&self.ptr.data);

                    var destroy_slice = @ptrCast([*]u8, self.ptr)[0..alloc_size];
                    alloc.inner.free(destroy_slice);
                }
            }
        };

        // Strong reference (i.e. the VmRef itself)
        // pub const Strong = {
        ptr: *Inner,

        const Strong = @This();
        pub fn get(self: Strong) *T {
            return &self.ptr.data;
        }

        pub fn clone(self: Strong) Strong {
            const old = self.ptr.block.strong.fetchAdd(1, .Monotonic);

            if (logging) std.log.debug("{*}: bumped strong count to {d}", .{ self.ptr, old + 1 });

            if (old > max_counter)
                @panic("too many refs");

            return Strong{ .ptr = self.ptr };
        }

        pub fn drop(self: Strong) void {
            // TODO extra debug field to track double drop
            const old = self.ptr.block.strong.fetchSub(1, .Release);
            if (logging) std.log.debug("{*}: dropped strong count to {d}", .{ self.ptr, old - 1 });
            if (old != 1) return;

            self.ptr.block.strong.fence(.Acquire);

            // destroy data
            T.vmRefDrop(self.ptr.data);

            // destroy implicit shared weak
            const implicit_weak = Weak{ .ptr = self.ptr };
            implicit_weak.drop();
        }

        pub fn cmpPtr(self: Strong, other: Strong) bool {
            return self.ptr == other.ptr;
        }
        // }; // end of Strong

        const InnerBlock = struct {
            weak: Counter,
            strong: Counter,
        };

        const Inner = struct {
            block: InnerBlock,
            data: T,
        };

        /// Data is undefined
        fn new_uninit(size: usize, comptime alignment: u29) !Strong {
            const alloc = global_allocator();
            const alloc_size = @sizeOf(InnerBlock) + size;
            const buf = try alloc.inner.allocAdvanced(u8, alignment, alloc_size, .exact);
            const inner = @ptrCast(*Inner, buf);
            inner.* = .{
                .block = .{
                    .weak = Counter.init(1),
                    .strong = Counter.init(1),
                },
                .data = undefined,
            };
            return Strong{ .ptr = inner };
        }

        /// Data is undefined
        fn new() !Strong {
            return new_uninit(0, @alignOf(T));
        }
    };
}

/// Global instance accessed by all VmRefs (threadlocal->global, not a real global so multiple JVMs can coexist in a process)
pub const VmAllocator = struct {
    // TODO actual gc
    inner: Allocator,
};

// TODO return jvm OutOfMemoryException instance? or is that for the caller?
/// Returned class data is still unintialised
pub fn allocClass() !object.VmClassRef.Strong {
    const ref = try object.VmClassRef.new();
    return ref;
}

test "alloc class" {
    // init global allocator
    const handle = try jvm.ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    const alloced = try allocClass();
    // everything is unintialised!!! just set this so it can be dropped
    defer alloced.drop();
}

test "vmref" {
    const VmInt = struct {
        actual_count: u16,

        const ActualInt = struct {
            elems: [150]u64,
        };

        // interface for VmRef
        fn vmRefDrop(_: @This()) void {}
        fn vmRefSize(self: *const @This()) usize {
            return self.actual_count;
        }
    };
    const IntRef = VmRef(VmInt);

    // init global allocator
    const handle = try jvm.ThreadEnv.initMainThread(std.testing.allocator, undefined);
    defer handle.deinit();

    // simulate runtime known size, like a class field count
    var runtime_sz: u16 = 25;
    const strong1 = try IntRef.new_uninit(runtime_sz, @alignOf(VmInt.ActualInt));
    strong1.get().* = VmInt{ .actual_count = runtime_sz };
    const strong2 = strong1.clone();

    const u32_ref = strong1.get();
    const actual_ref = @ptrCast(*VmInt.ActualInt, u32_ref);
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
