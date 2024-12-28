const std = @import("std");

const Options = @import("build/Options.zig");
const LibCInstallStep = @import("build/LibCInstallStep.zig");
const TestResult = @import("build/TestResult.zig");

const TopLevelStep = struct {
    pub const base_id: std.Build.Step.Id = .top_level;

    step: std.Build.Step,
    description: []const u8,
};

fn appendUnique(list: *std.ArrayList([]const u8), value: []const u8) !bool {
    for (list.items) |item| {
        if (std.mem.eql(u8, item, value)) return false;
    }

    try list.append(value);
    return true;
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "whether to statically or dynamically link the library") orelse .static;
    const strict_dealloc = b.option(bool, "strict-dealloc", "whether to enforce deallocations") orelse (optimize == .Debug);

    const hdrgen = b.addExecutable(.{
        .name = "hdrgen",
        .target = b.graph.host,
        .root_source_file = b.path("tools/hdrgen.zig"),
    });

    hdrgen.root_module.addAnonymousImport("nulibc", .{
        .root_source_file = b.path("lib/nulibc.zig"),
        .imports = &.{
            .{
                .name = "options",
                .module = (Options{
                    .use_exports = false,
                    .strict_dealloc = strict_dealloc,
                    .target = target.result,
                }).make(b).createModule(),
            },
        },
    });

    const include_wf = b.addNamedWriteFiles("include");

    const hdrgen_step = b.addRunArtifact(hdrgen);
    hdrgen_step.addDirectorySourceArg(.{ .generated = .{
        .file = &include_wf.generated_directory,
    } });

    const libc = std.Build.Step.Compile.create(b, .{
        .name = "c",
        .kind = .lib,
        .linkage = linkage,
        .version = .{
            .major = 6,
            .minor = 0,
            .patch = 0,
        },
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("lib/nulibc.zig"),
        },
    });

    libc.no_builtin = true;

    libc.step.dependOn(&hdrgen_step.step);

    libc.installHeadersDirectory(.{ .generated = .{
        .file = &include_wf.generated_directory,
    } }, ".", .{});

    libc.root_module.addOptions("options", (Options{
        .use_exports = true,
        .strict_dealloc = strict_dealloc,
        .target = null,
    }).make(b));

    b.installArtifact(libc);

    const crtc_wf = b.addWriteFiles();

    const crt1 = if (target.result.os.tag == .linux) blk: {
        const crt1 = b.addObject(.{
            .name = "crt1",
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("startup/crt1.zig"),
        });

        _ = crtc_wf.addCopyFile(crt1.getEmittedBin(), "crt1.o");

        b.getInstallStep().dependOn(&b.addInstallArtifact(crt1, .{
            .dest_dir = .{
                .override = .lib,
            },
        }).step);

        break :blk crt1;
    } else null;

    const libc_install = LibCInstallStep.create(b, .{
        .crt_dir = crtc_wf.getDirectory(),
        .include_dir = include_wf.getDirectory(),
        .sys_include_dir = include_wf.getDirectory(),
    });

    const can_execute = target.query.isNative() or b.enable_qemu;
    const test_step = b.step("test", "run all unit tests");

    if (can_execute) {
        var tests_dir = std.fs.openDirAbsolute(b.pathFromRoot("tests"), .{
            .iterate = true,
        }) catch @panic("Failed to open tests");
        defer tests_dir.close();

        var tests_dir_iter = tests_dir.iterate();
        while (tests_dir_iter.next() catch @panic("Failed to iterate tests")) |category| {
            if (category.kind != .directory) continue;

            const test_category = blk: {
                const step_info = b.allocator.create(TopLevelStep) catch @panic("OOM");
                step_info.* = .{
                    .step = std.Build.Step.init(.{
                        .id = TopLevelStep.base_id,
                        .name = b.dupe(category.name),
                        .owner = b,
                    }),
                    .description = b.fmt("Test functions in {s}", .{category.name}),
                };
                break :blk &step_info.step;
            };

            var category_dir = std.fs.openDirAbsolute(b.pathFromRoot(b.pathResolve(&.{
                "tests",
                category.name,
            })), .{
                .iterate = true,
            }) catch @panic("Failed to open tests");
            defer category_dir.close();

            var tests = std.ArrayList([]const u8).init(b.allocator);
            defer {
                for (tests.items) |item| b.allocator.free(item);
                tests.deinit();
            }

            var iter = category_dir.iterate();
            while (iter.next() catch @panic("Failed to iterate tests")) |test_entry| {
                if (test_entry.kind != .file) {
                    std.debug.panic("tests/{s}/{s} is not a file", .{ category.name, test_entry.name });
                }

                _ = appendUnique(&tests, b.dupe(std.fs.path.stem(test_entry.name))) catch @panic("OOM");
            }

            for (tests.items) |test_name| {
                const full_test_name = b.fmt("test_{s}_{s}", .{ category.name, test_name });
                const result = TestResult.load(b, category.name, test_name);

                const test_exec = b.addExecutable(.{
                    .name = full_test_name,
                    .target = target,
                    .optimize = optimize,
                });

                test_exec.addCSourceFile(.{
                    .file = b.path(b.pathResolve(&.{
                        "tests",
                        category.name,
                        b.fmt("{s}.c", .{test_name}),
                    })),
                });

                test_exec.step.dependOn(&libc_install.step);

                test_exec.setLibCFile(.{
                    .generated = .{
                        .file = &libc_install.generated_file,
                    },
                });

                test_exec.no_builtin = true;

                // TODO: replace with linkLibC once we support enough.
                test_exec.linkLibrary(libc);
                if (crt1) |obj| test_exec.addObject(obj);

                const test_run = b.addRunArtifact(test_exec);
                test_run.setName(b.dupe(test_name));
                test_run.expectExitCode(result.exit_code);
                test_run.expectStdErrEqual(std.mem.join(b.allocator, "\n", result.stderr) catch @panic("OOM"));
                test_run.expectStdOutEqual(std.mem.join(b.allocator, "\n", result.stdout) catch @panic("OOM"));

                test_category.dependOn(&test_run.step);
            }

            test_step.dependOn(test_category);
        }
    }
}
