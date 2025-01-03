const std = @import("std");
const options = @import("options");

pub fn strnlen(s: [*:0]const c_char, maxlen: usize) callconv(.C) usize {
    return std.mem.indexOfSentinel(c_char, 0, @ptrCast(s[0..maxlen]));
}

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            @export(&strnlen, .{ .name = "strnlen" });
        }
    }
}
