const options = @import("options");

pub const assert = @import("assert/assert.zig");

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            _ = assert;
        }
    }
}
