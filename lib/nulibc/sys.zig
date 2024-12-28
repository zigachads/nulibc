pub const auxv = @import("sys/auxv.zig");

comptime {
    _ = auxv;
}
