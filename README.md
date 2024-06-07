# zig-jvm

A Java Virtual Machine implementation in Zig.

## Goals

* Run Minecraft with **playable** performance
    * Ideally the opcode interpreter will be fast enough, but a JIT isn't out of the question.
* Provide an API to **create and destroy multiple JVMs within the same process**
    * Every existing JVM I've looked at uses globals, doesn't clean up after shutdown, and can't be
        coexist with other instances in the same process.

This makes use of the system Java class files from `OpenJDK 18`, and reimplements all native code.

Linux only for now.

## Features

* ✅ Class parsing and loading
* 🚧 Module support
* 🚧 Implement all opcodes
    * ✅ Implement most important (field access, method calling, conditionals, arithmetic)
    * 🚧 Implement the rest of them
* ✅ Exceptions (see test case [src/test/Throw.java]([src/test/Throw.java]))
* ✅ Native function resolving and invoking (via `libffi`)
* 🚧 Java Native Interface (JNI)
    * ✅ `JNIEnv*` passed to native functions
    * 🚧 Actually implement these native functions
* 🚧 Multiple threads, monitors, `synchronized` methods

(🚧 = in progress or planned)


### Example logfile

A snippet from the logs to show the current capabilities:

```
...
debug: executing java/lang/Throwable.fillInStackTrace
debug: call stack:
 * 0) java/lang/Throwable.fillInStackTrace (pc=0)
 * 1) java/lang/Throwable.<init> (pc=24)
 * 2) java/lang/Exception.<init> (pc=2)
 * 3) java/io/IOException.<init> (pc=2)
 * 4) java/io/FileNotFoundException.<init> (pc=2)
 * 5) Throw.vmTest (pc=6)
debug: operand stack: {}
debug: local vars: [#0: reference, java/io/FileNotFoundException@7f4ab77b7f00]
debug: pc=0: aload_0
debug: operand stack: pushed #1 (reference): java/io/FileNotFoundException@7f4ab77b7f00
debug: operand stack: {#0: reference, java/io/FileNotFoundException@7f4ab77b7f00}
debug: local vars: [#0: reference, java/io/FileNotFoundException@7f4ab77b7f00]
debug: pc=1: getfield
debug: resolving class java/lang/Throwable
debug: operand stack: popped #0 (reference): java/io/FileNotFoundException@7f4ab77b7f00
debug: operand stack: pushed #1 (reference): [java/lang/StackTraceElement@7f4ab780ce00
debug: getfield(java/io/FileNotFoundException@7f4ab77b7f00, stackTrace) = [java/lang/StackTraceElement@7f4ab780ce00
debug: operand stack: {#0: reference, [java/lang/StackTraceElement@7f4ab780ce00}
debug: local vars: [#0: reference, java/io/FileNotFoundException@7f4ab77b7f00]
debug: pc=4: ifnonnull
debug: operand stack: popped #0 (reference): [java/lang/StackTraceElement@7f4ab780ce00
debug: operand stack: {}
debug: local vars: [#0: reference, java/io/FileNotFoundException@7f4ab77b7f00]
debug: pc=14: aload_0
debug: operand stack: pushed #1 (reference): java/io/FileNotFoundException@7f4ab77b7f00
debug: operand stack: {#0: reference, java/io/FileNotFoundException@7f4ab77b7f00}
debug: local vars: [#0: reference, java/io/FileNotFoundException@7f4ab77b7f00]
debug: pc=15: iconst_0
debug: operand stack: pushed #2 (int): 0
debug: operand stack: {#0: reference, java/io/FileNotFoundException@7f4ab77b7f00, #1: int, 0}
debug: local vars: [#0: reference, java/io/FileNotFoundException@7f4ab77b7f00]
debug: pc=16: invokevirtual
debug: resolving class java/lang/Throwable
debug: resolved method to java/io/FileNotFoundException.fillInStackTrace
debug: executing java/io/FileNotFoundException.fillInStackTrace
debug: binding native method
debug: looking for 'Java_java_lang_Throwable_fillInStackTrace'
debug: call stack:
 * 0) java/io/FileNotFoundException.fillInStackTrace (native)
 * 1) java/lang/Throwable.fillInStackTrace (pc=16)
 * 2) java/lang/Throwable.<init> (pc=24)
 * 3) java/lang/Exception.<init> (pc=2)
 * 4) java/io/IOException.<init> (pc=2)
 * 5) java/io/FileNotFoundException.<init> (pc=2)
 * 6) Throw.vmTest (pc=6)
```

## Usage

Please note that this is:
* very much WIP
* built with the Zig master branch, and is randomly updated to the latest
    (currently `0.13.0-dev.365+332fbb4b0`).
* will be very unlikely to run arbitrary Java programs any time soon

The way I am progressing through the massive amount of functionality expected from a JVM is to build
up a supply of small programs that exercise different parts of the JVM. These programs are in
`src/test`, and can be run as follows:

* Extract the JDK modules file to a directory (until modules are supported)
    * `jimage extract --dir $EXTRACT_DIR /usr/lib/jvm/java-18-openjdk/lib/modules`
    * This should give a directory structure where `java.base/java/lang/Object.class` exists
* `zig build run-testrunner -- -Xbootclasspath $EXTRACT_DIR/java.base`

If you're feeling brave, you can run a given class file, just like the normal `java` command. Don't
expect it to work though.

If `Test.class` is in `$CLASS_DIR`, then run
    `zig build run-java -- -Xbootclasspath $EXTRACT_DIR:$CLASS_DIR Test`


# Why?

First of all, why not? This is a great technical project that constantly stretches me.

Also this is my second iteration of implementing a JVM, the [first is in Rust](https://github.com/DomWilliams0/jvm) and is still pretty incomplete, but suffers from some over-the-top type safety that I wanted to reduce in a second iteration, which would also help with performance.
