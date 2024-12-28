const std = @import("std");

pub fn strlen(s: [*c]const c_char) callconv(.C) usize {
    return std.mem.len(@as([*c]const u8, @ptrCast(@alignCast(s))));
}

comptime {
    @export(&strlen, .{ .name = "strlen" });
}
