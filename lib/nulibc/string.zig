const builtins = @import("builtins");
const options = @import("options");
const target = options.target orelse builtins.target;

pub const size_t = switch (target.ptrBitWidth()) {
    16 => u16,
    32 => u32,
    64 => u64,
    else => @compileError("Incompatible CPU bit width"),
};

pub const ssize_t = switch (target.ptrBitWidth()) {
    16 => i16,
    32 => i32,
    64 => i64,
    else => @compileError("Incompatible CPU bit width"),
};

pub const memcpy = @import("string/memcpy.zig");
pub const memmove = @import("string/memmove.zig");
pub const memset = @import("string/memset.zig");
pub const strlen = @import("string/strlen.zig");
pub const strnlen = @import("string/strnlen.zig");

comptime {
    if (options.lib_variant) |lib_variant| {
        if (lib_variant == .c) {
            _ = memcpy;
            _ = memmove;
            _ = memset;
            _ = strlen;
            _ = strnlen;
        }
    }
}
