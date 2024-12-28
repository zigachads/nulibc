const internal = @import("../internal.zig");

pub fn free(ptr: *anyopaque) callconv(.C) void {
    internal.malloc_table_mutex.lock();
    defer internal.malloc_table_mutex.unlock();

    const alloc = internal.gpa.allocator();

    for (internal.malloc_table.items, 0..) |item, i| {
        if (item.ptr == ptr) {
            _ = internal.malloc_table.orderedRemove(i);
            alloc.free(@as([*]const u8, @ptrCast(@alignCast(ptr)))[0..item.size]);
            return;
        }
    }

    internal.log.err("free({*}) failed: could not determine size", .{ptr});
}

comptime {
    @export(&free, .{ .name = "free" });
}
