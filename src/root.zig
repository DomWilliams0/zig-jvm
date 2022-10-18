pub const alloc = @import("alloc.zig");
pub const bootstrap = @import("bootstrap.zig");
pub const cafebabe = @import("cafebabe.zig");
pub const classloader = @import("classloader.zig");
pub const descriptor = @import("descriptor.zig");
pub const frame = @import("frame.zig");
pub const insn = @import("insn.zig");
pub const interpreter = @import("interpreter.zig");
pub const jni = @import("jni.zig");
pub const state = @import("state.zig");
pub const native = @import("native.zig");
pub const object = @import("object.zig");
pub const types = @import("type.zig");

pub const VmObjectRef = object.VmObjectRef;
pub const VmClassRef = object.VmClassRef;

usingnamespace @import("natives/natives.zig");