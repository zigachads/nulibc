const options = @import("options");

pub fn memset(dest: [*]c_int, c: c_int, n: usize) callconv(.C) [*]const c_int {
    @memset(dest[0..n], c);
    return dest;
}

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            @export(&memset, .{ .name = "memset" });
        }
    }
}
