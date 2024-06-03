const std = @import("std");

/// As defined in jdk/internal/util/SystemProps$Raw
const PropertyIndices = struct {
    const _display_country_NDX = 0;
    const _display_language_NDX = 1 + _display_country_NDX;
    const _display_script_NDX = 1 + _display_language_NDX;
    const _display_variant_NDX = 1 + _display_script_NDX;
    const _file_encoding_NDX = 1 + _display_variant_NDX;
    const _file_separator_NDX = 1 + _file_encoding_NDX;
    const _format_country_NDX = 1 + _file_separator_NDX;
    const _format_language_NDX = 1 + _format_country_NDX;
    const _format_script_NDX = 1 + _format_language_NDX;
    const _format_variant_NDX = 1 + _format_script_NDX;
    const _ftp_nonProxyHosts_NDX = 1 + _format_variant_NDX;
    const _ftp_proxyHost_NDX = 1 + _ftp_nonProxyHosts_NDX;
    const _ftp_proxyPort_NDX = 1 + _ftp_proxyHost_NDX;
    const _http_nonProxyHosts_NDX = 1 + _ftp_proxyPort_NDX;
    const _http_proxyHost_NDX = 1 + _http_nonProxyHosts_NDX;
    const _http_proxyPort_NDX = 1 + _http_proxyHost_NDX;
    const _https_proxyHost_NDX = 1 + _http_proxyPort_NDX;
    const _https_proxyPort_NDX = 1 + _https_proxyHost_NDX;
    const _java_io_tmpdir_NDX = 1 + _https_proxyPort_NDX;
    const _line_separator_NDX = 1 + _java_io_tmpdir_NDX;
    const _os_arch_NDX = 1 + _line_separator_NDX;
    const _os_name_NDX = 1 + _os_arch_NDX;
    const _os_version_NDX = 1 + _os_name_NDX;
    const _path_separator_NDX = 1 + _os_version_NDX;
    const _socksNonProxyHosts_NDX = 1 + _path_separator_NDX;
    const _socksProxyHost_NDX = 1 + _socksNonProxyHosts_NDX;
    const _socksProxyPort_NDX = 1 + _socksProxyHost_NDX;
    const _sun_arch_abi_NDX = 1 + _socksProxyPort_NDX;
    const _sun_arch_data_model_NDX = 1 + _sun_arch_abi_NDX;
    const _sun_cpu_endian_NDX = 1 + _sun_arch_data_model_NDX;
    const _sun_cpu_isalist_NDX = 1 + _sun_cpu_endian_NDX;
    const _sun_io_unicode_encoding_NDX = 1 + _sun_cpu_isalist_NDX;
    const _sun_jnu_encoding_NDX = 1 + _sun_io_unicode_encoding_NDX;
    const _sun_os_patch_level_NDX = 1 + _sun_jnu_encoding_NDX;
    const _sun_stderr_encoding_NDX = 1 + _sun_os_patch_level_NDX;
    const _sun_stdout_encoding_NDX = 1 + _sun_stderr_encoding_NDX;
    const _user_dir_NDX = 1 + _sun_stdout_encoding_NDX;
    const _user_home_NDX = 1 + _user_dir_NDX;
    const _user_name_NDX = 1 + _user_home_NDX;
    const _LENGTH = 1 + _user_name_NDX;
};

pub const PlatformProperties = struct {
    display_country: ?[:0]const u8 = null,
    display_language: ?[:0]const u8 = null,
    display_script: ?[:0]const u8 = null,
    display_variant: ?[:0]const u8 = null,
    file_encoding: ?[:0]const u8 = null,
    file_separator: ?[:0]const u8 = null,
    format_country: ?[:0]const u8 = null,
    format_language: ?[:0]const u8 = null,
    format_script: ?[:0]const u8 = null,
    format_variant: ?[:0]const u8 = null,
    ftp_nonProxyHosts: ?[:0]const u8 = null,
    ftp_proxyHost: ?[:0]const u8 = null,
    ftp_proxyPort: ?[:0]const u8 = null,
    http_nonProxyHosts: ?[:0]const u8 = null,
    http_proxyHost: ?[:0]const u8 = null,
    http_proxyPort: ?[:0]const u8 = null,
    https_proxyHost: ?[:0]const u8 = null,
    https_proxyPort: ?[:0]const u8 = null,
    java_io_tmpdir: ?[:0]const u8 = null,
    line_separator: ?[:0]const u8 = null,
    os_arch: ?[:0]const u8 = null,
    os_name: ?[:0]const u8 = null,
    os_version: ?[:0]const u8 = null,
    path_separator: ?[:0]const u8 = null,
    socksNonProxyHosts: ?[:0]const u8 = null,
    socksProxyHost: ?[:0]const u8 = null,
    socksProxyPort: ?[:0]const u8 = null,
    sun_arch_abi: ?[:0]const u8 = null,
    sun_arch_data_model: ?[:0]const u8 = null,
    sun_cpu_endian: ?[:0]const u8 = null,
    sun_cpu_isalist: ?[:0]const u8 = null,
    sun_io_unicode_encoding: ?[:0]const u8 = null,
    sun_jnu_encoding: ?[:0]const u8 = null,
    sun_os_patch_level: ?[:0]const u8 = null,
    sun_stderr_encoding: ?[:0]const u8 = null,
    sun_stdout_encoding: ?[:0]const u8 = null,
    user_dir: ?[:0]const u8 = null,
    user_home: ?[:0]const u8 = null,
    user_name: ?[:0]const u8 = null,

    pub fn fetch(alloc: std.mem.Allocator) error{ OutOfMemory, Internal }!PlatformProperties {
        var props = PlatformProperties{};

        // TODO better non-env reliant way of getting user things
        if (std.posix.getenv("HOME")) |s| props.user_home = try alloc.dupeZ(u8, s);
        if (std.posix.getenv("USER")) |s| props.user_name = try alloc.dupeZ(u8, s);

        {
            var buf = try alloc.alloc(u8, std.fs.MAX_NAME_BYTES);
            const path = std.fs.cwd().realpath(".", buf) catch return error.Internal;
            buf[path.len] = 0; // manually null terminate
            props.user_dir = buf[0..path.len :0];
        }

        const builtin = @import("builtin");
        const big_endian = builtin.cpu.arch.endian() == .big;
        // TODO not portable
        props.java_io_tmpdir = "/tmp";
        props.sun_cpu_endian = if (big_endian) "big" else "little";

        const uname = std.posix.uname();
        // std.mem.span doesn't get the length properly
        props.os_name = try alloc.dupeZ(u8, uname.sysname[0..std.mem.indexOfSentinel(u8, 0, &uname.sysname)]);
        props.os_version = try alloc.dupeZ(u8, uname.release[0..std.mem.indexOfSentinel(u8, 0, &uname.release)]);
        props.os_arch = @tagName(builtin.cpu.arch);

        // TODO get actual lang
        props.display_language = "en";
        props.sun_io_unicode_encoding = if (big_endian) "UnicodeBig" else "UnicodeLittle";
        props.sun_jnu_encoding = "UTF-8";

        props.file_separator = comptime &.{std.fs.path.sep}; // TODO is this a local?
        props.path_separator = ":";
        props.line_separator = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";

        return props;
    }

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        if (self.user_home) |s| alloc.free(s);
        if (self.user_name) |s| alloc.free(s);
        if (self.user_dir) |s| alloc.free(s);
        if (self.os_name) |s| alloc.free(s);
        if (self.os_version) |s| alloc.free(s);
    }

    pub fn toArray(self: @This()) [PropertyIndices._LENGTH]?[:0]const u8 {
        var arr: [PropertyIndices._LENGTH]?[:0]const u8 = .{null} ** PropertyIndices._LENGTH;

        inline for (@typeInfo(@This()).Struct.fields) |f| {
            const value = @field(self, f.name);
            if (value) |str| {
                // @compileLog(str);
                std.log.debug("PlatformProperties[{s}] = \"{any}\"", .{ f.name, std.fmt.fmtSliceEscapeLower(str) });
                const idx = @field(PropertyIndices, std.fmt.comptimePrint("_{s}_NDX", .{f.name}));
                arr[idx] = value;
            }
        }

        return arr;
    }
};

const arg = @import("arg.zig");
pub const SystemProperties = struct {
    java_home: [:0]const u8,
    java_vm_specification_name: [:0]const u8,
    java_vm_specification_vendor: [:0]const u8,
    java_vm_specification_version: [:0]const u8,
    java_vm_version: [:0]const u8,
    java_vm_name: [:0]const u8,

    // java_class_path: [:0]const u8,
    // java_library_path: [:0]const u8,

    pub fn fetch(args: *const arg.JvmArgs) SystemProperties {
        _ = args;
        // TODO rewrite arg parsing then pass this in
        return .{
            .java_home = "/usr/lib/jvm/java-19-openjdk",
            .java_vm_specification_name = "Java Virtual Machine Specification",
            .java_vm_specification_vendor = "Oracle Corporation",
            .java_vm_specification_version = "18",
            .java_vm_name = "ZigJVM",
            .java_vm_version = "0.1",
        };
    }

    pub fn keyValues(self: @This()) [@typeInfo(@This()).Struct.fields.len][2][:0]const u8 {
        // const fields = @typeInfo(@This()).Struct.fields;
        // comptime var out: [fields.len][2][:0]const u8 = undefined;

        // inline for (fields, 0..) |f, i| {
        //     comptime var key: [f.name.len:0]u8 = undefined;
        //     comptime {
        //         @memcpy(&key, f.name);
        //         std.mem.replaceScalar(u8, &key, '_', '.');
        //         out[i][0] = &key;
        //         out[i][1] = "shit"; // @field(self, f.name);
        //     }
        // }

        // const final_out = out;
        // return final_out;
        _ = self;
        @panic("shit");
    }
};
