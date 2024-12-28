const options = @import("options");

pub const size_t = u64;

pub const memcpy = @import("string/memcpy.zig");
pub const memset = @import("string/memset.zig");
pub const strlen = @import("string/strlen.zig");
pub const strnlen = @import("string/strnlen.zig");

comptime {
    if (options.use_exports) {
        _ = memcpy;
        _ = memset;
        _ = strlen;
        _ = strnlen;
    }
}
