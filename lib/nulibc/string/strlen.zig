const std = @import("std");
const options = @import("options");

pub fn strlen(s: [*c]const c_char) callconv(.C) usize {
    return std.mem.len(@as([*c]const u8, @ptrCast(@alignCast(s))));
}

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            @export(&strlen, .{ .name = "strlen" });
        }
    }
}
