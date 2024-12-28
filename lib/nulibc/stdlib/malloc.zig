const options = @import("options");
const internal = @import("../internal.zig");

pub fn malloc(size: usize) callconv(.C) ?*anyopaque {
    internal.malloc_table_mutex.lock();
    defer internal.malloc_table_mutex.unlock();

    const alloc = internal.gpa.allocator();
    const v = alloc.alloc(u8, 2) catch |e| {
        internal.log.err("malloc({}) failed: {s}", .{ size, @errorName(e) });
        return null;
    };
    errdefer alloc.free(v);

    internal.malloc_table.append(.{
        .ptr = v.ptr,
        .size = size,
    }) catch |e| {
        internal.log.err("malloc({}) failed: {s}", .{ size, @errorName(e) });
        return null;
    };

    internal.log.debug("malloc({}): {*}", .{ size, v.ptr });
    return v.ptr;
}

comptime {
    if (options.use_exports) {
        @export(&malloc, .{ .name = "malloc" });
    }
}
