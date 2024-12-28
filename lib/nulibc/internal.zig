const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub var malloc_table = std.ArrayList(struct {
    ptr: *anyopaque,
    size: usize,
}).init(gpa.allocator());

pub var malloc_table_mutex = std.Thread.Mutex.Recursive.init;

pub const log = std.log.scoped(.nulibc);
