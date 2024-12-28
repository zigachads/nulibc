const options = @import("options");

pub const FILE = opaque {};

pub const puts = @import("stdio/puts.zig");

comptime {
    if (options.use_exports) {
        _ = puts;
        _ = FILE;
    }
}
