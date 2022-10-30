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
    display_country: [*c]const u8,
    display_language: [*c]const u8,
    display_script: [*c]const u8,
    display_variant: [*c]const u8,
    file_encoding: [*c]const u8,
    file_separator: [*c]const u8,
    format_country: [*c]const u8,
    format_language: [*c]const u8,
    format_script: [*c]const u8,
    format_variant: [*c]const u8,
    ftp_nonProxyHosts: [*c]const u8,
    ftp_proxyHost: [*c]const u8,
    ftp_proxyPort: [*c]const u8,
    http_nonProxyHosts: [*c]const u8,
    http_proxyHost: [*c]const u8,
    http_proxyPort: [*c]const u8,
    https_proxyHost: [*c]const u8,
    https_proxyPort: [*c]const u8,
    java_io_tmpdir: [*c]const u8,
    line_separator: [*c]const u8,
    os_arch: [*c]const u8,
    os_name: [*c]const u8,
    os_version: [*c]const u8,
    path_separator: [*c]const u8,
    socksNonProxyHosts: [*c]const u8,
    socksProxyHost: [*c]const u8,
    socksProxyPort: [*c]const u8,
    sun_arch_abi: [*c]const u8,
    sun_arch_data_model: [*c]const u8,
    sun_cpu_endian: [*c]const u8,
    sun_cpu_isalist: [*c]const u8,
    sun_io_unicode_encoding: [*c]const u8,
    sun_jnu_encoding: [*c]const u8,
    sun_os_patch_level: [*c]const u8,
    sun_stderr_encoding: [*c]const u8,
    sun_stdout_encoding: [*c]const u8,
    user_dir: [*c]const u8,
    user_home: [*c]const u8,
    user_name: [*c]const u8,

    pub fn fetch() PlatformProperties {
        var props = std.mem.zeroes(PlatformProperties);

        // TODO more props
        if (std.os.getenv("HOME")) |s| props.user_home = s.ptr;

        return props;
    }

    pub fn toArray(self: @This()) [PropertyIndices._LENGTH][*c]const u8 {
        var arr: [PropertyIndices._LENGTH][*c]const u8 = .{null} ** PropertyIndices._LENGTH;

        inline for (@typeInfo(@This()).Struct.fields) |f| {
            const value = @field(self, f.name);
            if (value) |str| {
                const idx = @field(PropertyIndices, std.fmt.comptimePrint("_{s}_NDX", .{f.name}));
                arr[idx] = str;
            }
        }

        return arr;
    }
};

test "asdf" {
    _ = PropertyIndices;
    _ = PlatformProperties;
}
