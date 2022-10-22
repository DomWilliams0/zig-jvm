const std = @import("std");
const sys = @import("sys");
const jvm = @import("jvm");

pub export fn Java_java_lang_Object_getClass(_: *anyopaque, this: sys.jobject) sys.jclass {
    const obj = sys.convert(sys.jobject).from(this).toStrongUnchecked(); // `this` can't be null
    const class = obj.get().class.get().getClassInstance().clone();
    return sys.convert(sys.jobject).to(class.intoNullable());
}

pub const methods = [_]@import("root.zig").JniMethod{
    // TODO auto declare these from javap with a script, allow unimplemented funcs
    .{.method = "Java_java_lang_Object_getClass", .desc = "()Ljava/lang/Class;"},
};