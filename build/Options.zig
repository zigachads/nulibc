const std = @import("std");
const Options = @This();

strict_dealloc: bool = false,
use_exports: bool = true,
target: ?std.Target = null,

pub fn make(options: Options, b: *std.Build) *std.Build.Step.Options {
    const step = b.addOptions();
    step.contents.appendSlice("const std = @import(\"std\");\n\n") catch @panic("OOM");

    step.addOption(bool, "use_exports", options.use_exports);
    step.addOption(bool, "strict_dealloc", options.strict_dealloc);

    // Based on "src/Builtin.zig"
    // https://github.com/ziglang/zig/blob/01081cc8e8b79104f7992d60dbd1bc8682e8fedf/src/Builtin.zig
    if (options.target) |target| {
        const generic_arch_name = target.cpu.arch.genericName();

        step.contents.writer().print(
            \\pub const object_format: ?std.Target.ObjectFormat = .{p_};
            \\pub const abi: ?std.Target.Abi = .{p_};
            \\pub const cpu: ?std.Target.Cpu = .{{
            \\    .arch = .{p_},
            \\    .model = &std.Target.{p_}.cpu.{p_},
            \\    .features = std.Target.{p_}.featureSet(&.{{
            \\
        , .{
            std.zig.fmtId(@tagName(target.ofmt)),
            std.zig.fmtId(@tagName(target.abi)),
            std.zig.fmtId(@tagName(target.cpu.arch)),
            std.zig.fmtId(generic_arch_name),
            std.zig.fmtId(target.cpu.model.name),
            std.zig.fmtId(generic_arch_name),
        }) catch @panic("OOM");

        for (target.cpu.arch.allFeaturesList(), 0..) |feature, index_usize| {
            const index = @as(std.Target.Cpu.Feature.Set.Index, @intCast(index_usize));
            const is_enabled = target.cpu.features.isEnabled(index);
            if (is_enabled) {
                step.contents.writer().print("        .{p_},\n", .{std.zig.fmtId(feature.name)}) catch @panic("OOM");
            }
        }

        step.contents.writer().print(
            \\    }}),
            \\}};
            \\pub const os: ?std.Target.Os = .{{
            \\    .tag = .{p_},
            \\    .version_range = .{{
        ,
            .{std.zig.fmtId(@tagName(target.os.tag))},
        ) catch @panic("OOM");

        switch (target.os.versionRange()) {
            .none => step.contents.appendSlice(" .none = {} },\n") catch @panic("OOM"),
            .semver => |semver| step.contents.writer().print(
                \\ .semver = .{{
                \\        .min = .{{
                \\            .major = {},
                \\            .minor = {},
                \\            .patch = {},
                \\        }},
                \\        .max = .{{
                \\            .major = {},
                \\            .minor = {},
                \\            .patch = {},
                \\        }},
                \\    }}}},
                \\
            , .{
                semver.min.major,
                semver.min.minor,
                semver.min.patch,

                semver.max.major,
                semver.max.minor,
                semver.max.patch,
            }) catch @panic("OOM"),
            .linux => |linux| step.contents.writer().print(
                \\ .linux = .{{
                \\        .range = .{{
                \\            .min = .{{
                \\                .major = {},
                \\                .minor = {},
                \\                .patch = {},
                \\            }},
                \\            .max = .{{
                \\                .major = {},
                \\                .minor = {},
                \\                .patch = {},
                \\            }},
                \\        }},
                \\        .glibc = .{{
                \\            .major = {},
                \\            .minor = {},
                \\            .patch = {},
                \\        }},
                \\        .android = {},
                \\    }}}},
                \\
            , .{
                linux.range.min.major,
                linux.range.min.minor,
                linux.range.min.patch,

                linux.range.max.major,
                linux.range.max.minor,
                linux.range.max.patch,

                linux.glibc.major,
                linux.glibc.minor,
                linux.glibc.patch,

                linux.android,
            }) catch @panic("OOM"),
            .windows => |windows| step.contents.writer().print(
                \\ .windows = .{{
                \\        .min = {c},
                \\        .max = {c},
                \\    }}}},
                \\
            , .{ windows.min, windows.max }) catch @panic("OOM"),
        }
        step.contents.appendSlice(
            \\};
            \\pub const target: ?std.Target = .{
            \\    .cpu = cpu,
            \\    .os = os,
            \\    .abi = abi,
            \\    .ofmt = object_format,
            \\
        ) catch @panic("OOM");

        if (target.dynamic_linker.get()) |dl| {
            step.contents.writer().print(
                \\    .dynamic_linker = .init("{s}"),
                \\}};
                \\
            , .{dl}) catch @panic("OOM");
        } else {
            step.contents.appendSlice(
                \\    .dynamic_linker = .none,
                \\};
                \\
            ) catch @panic("OOM");
        }
    } else {
        step.contents.appendSlice(
            \\pub const object_format: ?std.Target.ObjectFormat = null;
            \\pub const abi: ?std.Target.Abi = null;
            \\pub const cpu: ?std.Target.Cpu = null;
            \\pub const os: ?std.Target.Os = null;
            \\pub const target: ?std.Target = null;
            \\
        ) catch @panic("OOM");
    }

    return step;
}
