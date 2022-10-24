# zig-jvm

A Java Virtual Machine implementation in Zig. The goal is to eventually be able to run Minecraft.

This makes use of the system Java class files from `OpenJDK 18`, and reimplements all native code.

Linux only for now.

## Usage

Please note that this is:
* very much WIP
* built with the Zig master branch, and is randomly updated to the latest
    (currently `0.10.0-dev.4418+99c3578f6`).
* will be very unlikely to run arbitrary Java programs any time soon

The way I am progressing through the massive amount of functionality expected from a JVM is to build
up a supply of small programs that exercise different parts of the JVM. These programs are in
`src/test`, and can be run as follows:

* Extract the JDK modules file to a directory (until modules are supported)
    * `jimage extract --dir $EXTRACT_DIR /usr/lib/jvm/java-18-openjdk/lib/modules`
    * This should give a directory structure where `java.base/java/lang/Object.class` exists
* `zig build run -- -testrunner -Xbootclasspath $EXTRACT_DIR`

If you're feeling brave, you can run a given class file, just like the normal `java` command. Don't
expect it to work though.

If `Test.class` is in `$CLASS_DIR`, then run
    `zig build run -- -Xbootclasspath $EXTRACT_DIR:$CLASS_DIR Test`


# Why?

First of all, why not? This is a great technical project that constantly stretches me.

Also this is my second iteration of implementing a JVM, the [first is in Rust](https://github.com/DomWilliams0/jvm) and is still pretty incomplete, but suffers from some over-the-top type safety that I wanted to reduce in a second iteration, which would also help with performance.
