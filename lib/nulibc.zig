const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");

const native_os = (options.os orelse builtin.os).tag;

pub const start = @import("nulibc/start.zig");
pub const stdlib = @import("nulibc/stdlib.zig");
pub const stdint = @import("nulibc/stdint.zig");
pub const stdio = @import("nulibc/stdio.zig");
pub const string = @import("nulibc/string.zig");
pub const sys = if (native_os == .linux) @import("nulibc/sys.zig") else null;

pub const std_options = std.Options{
    .log_level = if (builtin.mode == .Debug) .debug else .err,
};

comptime {
    if (options.use_exports) {
        _ = start;
        _ = stdlib;
        _ = stdint;
        _ = stdio;
        _ = string;
        _ = sys;
    }
}
