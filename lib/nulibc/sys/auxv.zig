const builtin = @import("builtin");
const options = @import("options");

pub const getauxval = @import("auxv/getauxval.zig");

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            _ = getauxval;
        }
    }
}
