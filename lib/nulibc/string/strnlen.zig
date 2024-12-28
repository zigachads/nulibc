const std = @import("std");

pub fn strnlen(s: [*:0]const c_char, maxlen: usize) callconv(.C) usize {
    return std.mem.indexOfSentinel(c_char, 0, @ptrCast(s[0..maxlen]));
}

comptime {
    @export(&strnlen, .{ .name = "strnlen" });
}
