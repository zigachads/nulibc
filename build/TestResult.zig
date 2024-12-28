const std = @import("std");
const TestResult = @This();

exit_code: u8,
stdout: []const []const u8,
stderr: []const []const u8,

pub fn load(b: *std.Build, category: []const u8, name: []const u8) TestResult {
    const path = b.pathFromRoot(b.pathJoin(&.{
        "tests",
        category,
        b.fmt("{s}.json", .{name}),
    }));

    var file = std.fs.openFileAbsolute(path, .{}) catch |e| std.debug.panic("Failed to open {s}: {s}", .{ path, @errorName(e) });
    defer file.close();

    const metadata = file.metadata() catch |e| std.debug.panic("Failed to read metadata {s}: {s}", .{ path, @errorName(e) });
    const contents = file.readToEndAlloc(b.allocator, metadata.size()) catch |e| std.debug.panic("Failed to read file {s}: {s}", .{ path, @errorName(e) });
    defer b.allocator.free(contents);

    return (std.json.parseFromSlice(TestResult, b.allocator, contents, .{
        .allocate = .alloc_always,
    }) catch |e| std.debug.panic("Failed to parse JSON {s}: {s}", .{ path, @errorName(e) })).value;
}
