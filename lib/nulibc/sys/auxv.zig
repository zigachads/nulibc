const builtin = @import("builtin");
const options = @import("options");

pub const getauxval = @import("auxv/getauxval.zig");

comptime {
    if (options.use_exports) {
        _ = getauxval;
    }
}
