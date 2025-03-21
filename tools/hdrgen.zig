const std = @import("std");
const nulibc = @import("nulibc");

const root_ns = @typeName(nulibc);

const Type = struct {
    header: []const u8,
    name: []const u8,
    source: []const u8,
    types: []const []const u8,
    required_by: ?[]const []const u8 = null,
    is_function: bool = false,

    pub fn deinit(self: *const Type, alloc: std.mem.Allocator) void {
        alloc.free(self.source);
        alloc.free(self.types);
        if (self.required_by) |v| alloc.free(v);
    }
};

const TypeArray = std.ArrayList(Type);

fn exists(self: std.fs.Dir, sub_path: []const u8, flags: std.fs.File.OpenFlags) bool {
    self.access(sub_path, flags) catch return false;
    return true;
}

fn appendUnique(list: *std.ArrayList([]const u8), value: []const u8) !bool {
    for (list.items) |item| {
        if (std.mem.eql(u8, item, value)) return false;
    }

    try list.append(value);
    return true;
}

fn fileNameForType(comptime T: type) ?[]const u8 {
    const t = @typeInfo(T);

    if (t == .pointer) {
        return fileNameForType(t.pointer.child);
    }

    return switch (T) {
        u8 => "uint8_t",
        u16 => "uint16_t",
        u32 => "uint32_t",
        u64 => "uint64_t",
        i8 => "int8_t",
        i16 => "int16_t",
        i32 => "int32_t",
        i64 => "int64_t",
        usize => "size_t",
        isize => "ssize_t",
        bool => "bool",
        else => null,
    };
}

fn formatType(comptime T: type, name: []const u8, writer: std.io.AnyWriter) !void {
    const t = @typeInfo(T);

    if (t == .@"fn") {
        try formatType(t.@"fn".return_type.?, @typeName(t.@"fn".return_type.?), writer);

        try writer.writeByte(' ');
        try writer.writeAll(name);
        try writer.writeByte('(');

        inline for (t.@"fn".params, 0..) |param, i| {
            const is_last = (t.@"fn".params.len - 1) == i;

            try formatType(param.type.?, @typeName(param.type.?), writer);

            // FIXME: this messes things up
            // if (param.is_noalias) try writer.writeAll(" restrict");
            try writer.print(" arg{}", .{i});
            if (!is_last) try writer.writeAll(", ");
        }

        try writer.writeAll(");");
    } else if (t == .pointer and T != *anyopaque) {
        if (t.pointer.is_const) try writer.writeAll("const ");
        if (t.pointer.is_volatile) try writer.writeAll("volatile ");

        try formatType(t.pointer.child, @typeName(t.pointer.child), writer);

        try writer.writeByte('*');
    } else {
        return writer.writeAll(switch (T) {
            c_char => "char",
            c_int => "int",
            c_long => "long",
            c_short => "short",
            c_ushort => "unsigned short",
            c_uint => "unsigned int",
            c_ulong => "unsigned long",
            c_ulonglong => "unsigned long long",
            void => "void",
            ?*anyopaque, *anyopaque => "void*",
            else => fileNameForType(T) orelse return error.UnknownType,
        });
    }
}

fn walkNamespace(ns: anytype, types: *TypeArray) !void {
    inline for (comptime std.meta.declarations(ns)) |decl| {
        const f = @field(ns, decl.name);
        const t = @typeInfo(@TypeOf(f));

        if (t == .type) {
            const i = @typeInfo(f);

            if (i == .@"opaque") {
                try types.append(.{
                    .types = try types.allocator.alloc([]const u8, 0),
                    .name = decl.name,
                    .header = "nulibc-types/" ++ decl.name ++ ".h",
                    .source = try std.fmt.allocPrint(types.allocator,
                        \\typedef struct _{s} {s};
                    , .{ decl.name, decl.name }),
                    .required_by = try types.allocator.dupe([]const u8, &.{
                        @typeName(ns)[(root_ns.len + 1)..] ++ ".h",
                    }),
                });
            } else if (i == .int) {
                var source = std.ArrayList(u8).init(types.allocator);
                defer source.deinit();

                try source.appendSlice("typedef ");
                const add_type = if (f == u8) blk: {
                    try source.appendSlice("unsigned char");
                    break :blk false;
                } else if (f == i8) blk: {
                    try source.appendSlice("signed char");
                    break :blk false;
                } else if (f == u16) blk: {
                    try source.appendSlice("unsigned short");
                    break :blk false;
                } else if (f == i16) blk: {
                    try source.appendSlice("signed short");
                    break :blk false;
                } else if (f == u32) blk: {
                    try source.appendSlice("unsigned int");
                    break :blk false;
                } else if (f == i32) blk: {
                    try source.appendSlice("signed int");
                    break :blk false;
                } else if (f == u64) blk: {
                    try source.appendSlice("unsigned long long");
                    break :blk false;
                } else if (f == i64) blk: {
                    try source.appendSlice("signed long long");
                    break :blk false;
                } else blk: {
                    try formatType(f, decl.name, source.writer().any());
                    break :blk true;
                };
                try source.appendSlice(" " ++ decl.name ++ ";");

                const inner_typename = if (add_type) fileNameForType(f) else null;

                try types.append(.{
                    .types = if (inner_typename) |td| try types.allocator.dupe([]const u8, &.{
                        td,
                    }) else try types.allocator.alloc([]const u8, 0),
                    .name = decl.name,
                    .header = "nulibc-types/" ++ decl.name ++ ".h",
                    .source = try source.toOwnedSlice(),
                    .required_by = try types.allocator.dupe([]const u8, &.{
                        @typeName(ns)[(root_ns.len + 1)..] ++ ".h",
                    }),
                });
            } else if (i == .@"enum") {
                var source = std.ArrayList(u8).init(types.allocator);
                defer source.deinit();

                try source.appendSlice("typedef enum {\n");

                inline for (i.@"enum".fields, 0..) |field, x| {
                    const is_last = (i.@"enum".fields.len - 1) == x;

                    try source.appendSlice("  " ++ field.name);
                    if (!is_last) try source.append(',');
                    try source.append('\n');
                }

                try source.appendSlice("} " ++ decl.name ++ ";");

                try types.append(.{
                    .types = try types.allocator.alloc([]const u8, 0),
                    .name = decl.name,
                    .header = "nulibc-types/" ++ decl.name ++ ".h",
                    .source = try source.toOwnedSlice(),
                    .required_by = try types.allocator.dupe([]const u8, &.{
                        @typeName(ns)[(root_ns.len + 1)..] ++ ".h",
                    }),
                });
            } else if (i == .@"struct") {
                if (i.@"struct".fields.len > 0) {
                    var source = std.ArrayList(u8).init(types.allocator);
                    defer source.deinit();

                    try source.appendSlice("typedef struct {\n");

                    var field_types = std.ArrayList([]const u8).init(types.allocator);
                    defer field_types.deinit();

                    inline for (i.@"struct".fields) |field| {
                        if (fileNameForType(field.type)) |pt| {
                            _ = try appendUnique(&field_types, pt);
                        }

                        try source.appendSlice("  ");
                        try formatType(field.type, @typeName(field.type), source.writer().any());
                        try source.appendSlice(" " ++ field.name ++ ";\n");
                    }

                    try source.appendSlice("} " ++ decl.name ++ ";");

                    try types.append(.{
                        .types = try field_types.toOwnedSlice(),
                        .name = decl.name,
                        .header = "nulibc-types/" ++ decl.name ++ ".h",
                        .source = try source.toOwnedSlice(),
                        .required_by = try types.allocator.dupe([]const u8, &.{
                            @typeName(ns)[(root_ns.len + 1)..] ++ ".h",
                        }),
                    });
                }

                try walkNamespace(f, types);
            }
        } else if (t == .@"fn") {
            if (comptime std.mem.endsWith(u8, @typeName(ns), decl.name)) {
                const hdrname = comptime blk: {
                    const name = @typeName(ns)[(root_ns.len + 1)..(std.mem.lastIndexOf(u8, @typeName(ns), ".") orelse unreachable)];
                    var output: [name.len]u8 = undefined;
                    _ = std.mem.replace(u8, name, ".", "/", output[0..]);
                    break :blk output ++ ".h";
                };

                var source = std.ArrayList(u8).init(types.allocator);
                defer source.deinit();

                try formatType(@TypeOf(f), decl.name, source.writer().any());

                var fn_types = std.ArrayList([]const u8).init(types.allocator);
                defer fn_types.deinit();

                if (fileNameForType(t.@"fn".return_type.?)) |rt| {
                    _ = try appendUnique(&fn_types, rt);
                }

                inline for (t.@"fn".params) |param| {
                    if (fileNameForType(param.type.?)) |pt| {
                        _ = try appendUnique(&fn_types, pt);
                    }
                }

                try types.append(.{
                    .header = hdrname,
                    .name = decl.name,
                    .source = try source.toOwnedSlice(),
                    .types = try fn_types.toOwnedSlice(),
                    .is_function = true,
                });
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var argv = try std.process.ArgIterator.initWithAllocator(alloc);
    defer argv.deinit();

    _ = argv.skip();

    var outdir = blk: {
        const path = argv.next() orelse @panic("Missing output directory.");
        if (std.fs.path.isAbsolute(path)) {
            break :blk try (std.fs.openDirAbsolute(path, .{}) catch |e| switch (e) {
                error.FileNotFound => blk2: {
                    try std.fs.makeDirAbsolute(path);
                    break :blk2 try std.fs.openDirAbsolute(path, .{});
                },
                else => e,
            });
        }

        break :blk try (std.fs.cwd().openDir(path, .{}) catch |e| switch (e) {
            error.FileNotFound => blk2: {
                try std.fs.cwd().makePath(path);
                break :blk2 try std.fs.cwd().openDir(path, .{});
            },
            else => e,
        });
    };
    defer outdir.close();

    var overlaydir = blk: {
        const path = argv.next() orelse @panic("Missing overlay directory.");
        if (std.fs.path.isAbsolute(path)) {
            break :blk try std.fs.openDirAbsolute(path, .{});
        }
        break :blk try std.fs.cwd().openDir(path, .{});
    };
    defer overlaydir.close();

    var types = TypeArray.init(alloc);
    defer {
        for (types.items) |t| t.deinit(alloc);
        types.deinit();
    }

    try walkNamespace(nulibc, &types);

    var headers = std.ArrayList([]const u8).init(alloc);
    defer headers.deinit();

    for (types.items) |t| {
        if (t.required_by) |rb| {
            for (rb) |it| {
                _ = try appendUnique(&headers, it);
            }
        }
        _ = try appendUnique(&headers, t.header);
    }

    for (headers.items) |h| {
        if (std.fs.path.dirname(h)) |parent| {
            outdir.makePath(parent) catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => return e,
            };
        }

        if (exists(overlaydir, h, .{})) {
            try overlaydir.copyFile(h, outdir, h, .{});
            continue;
        }

        var file = try outdir.createFile(h, .{});
        defer file.close();

        try file.writer().writeAll(
            \\#pragma once
            \\
            \\
        );

        var inner_types = std.ArrayList([]const u8).init(alloc);
        defer inner_types.deinit();

        var fn_count: usize = 0;

        for (types.items) |t| {
            if (t.required_by) |rb| {
                for (rb) |it| {
                    if (!std.mem.eql(u8, h, it)) continue;

                    _ = try appendUnique(&inner_types, t.name);
                }
            }

            for (t.types) |it| {
                if (!std.mem.eql(u8, h, t.header)) continue;

                _ = try appendUnique(&inner_types, it);
                if (t.is_function) fn_count += 1;
            }
        }

        for (inner_types.items) |it| {
            const need_relpath = if (std.fs.path.dirname(h)) |parent| std.mem.eql(u8, parent, "nulibc-types") else false;

            if (need_relpath) {
                try file.writer().print(
                    \\#include "{s}.h"
                    \\
                , .{it});
            } else {
                try file.writer().print(
                    \\#include "nulibc-types/{s}.h"
                    \\
                , .{it});
            }
        }

        if (inner_types.items.len > 0 and fn_count > 0) try file.writer().writeByte('\n');

        for (types.items) |t| {
            if (!std.mem.eql(u8, h, t.header)) continue;

            try file.writer().writeAll(t.source);
            try file.writer().writeByte('\n');
        }
    }
}
