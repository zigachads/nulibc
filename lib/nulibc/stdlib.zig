const options = @import("options");

pub const free = @import("stdlib/free.zig");
pub const malloc = @import("stdlib/malloc.zig");

comptime {
    if (options.use_exports) {
        _ = free;
        _ = malloc;
    }
}
