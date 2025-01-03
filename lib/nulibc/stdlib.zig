const options = @import("options");

pub const free = @import("stdlib/free.zig");
pub const malloc = @import("stdlib/malloc.zig");

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            _ = free;
            _ = malloc;
        }
    }
}
