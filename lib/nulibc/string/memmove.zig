const options = @import("options");

pub fn memmove(noalias dest: [*]u8, noalias src: [*]const u8, n: usize) callconv(.C) [*]const u8 {
    if (@intFromPtr(dest) < @intFromPtr(src)) {
        for (dest[0..n], src[0..n]) |*d, s| d.* = s;
    } else {
        var i = n;
        while (i != 0) {
            i -= 1;
            dest[i] = src[i];
        }
    }
    return dest;
}

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            @export(&memmove, .{ .name = "memmove" });
        }
    }
}
