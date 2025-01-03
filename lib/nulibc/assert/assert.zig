const std = @import("std");
const options = @import("options");

pub fn assert(expr: bool) callconv(.C) void {
    std.debug.assert(expr);
}

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            @export(&assert, .{ .name = "assert" });
        }
    }
}
