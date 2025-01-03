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
    var target = b.standardTargetOptions(.{});

    target.result.dynamic_linker = std.Target.DynamicLinker.none;

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
                    .strict_dealloc = strict_dealloc,
                    .target = target.result,
                    .lib_variant = null,
                }).make(b).createModule(),
            },
        },
    });

    const include_wf = b.addNamedWriteFiles("include");

    const hdrgen_step = b.addRunArtifact(hdrgen);
    hdrgen_step.addDirectorySourceArg(.{ .generated = .{
        .file = &include_wf.generated_directory,
    } });

    hdrgen_step.addDirectorySourceArg(b.path("include"));

    const libdir_wf = b.addWriteFiles();

    @setEvalBranchQuota(100_000);
    inline for (comptime std.meta.fieldNames(std.builtin.LinkMode)) |linkage_name| {
        const sub_linkage = comptime (std.meta.stringToEnum(std.builtin.LinkMode, linkage_name) orelse unreachable);
        inline for (comptime std.meta.fieldNames(Options.LibVariant)) |lib_variant_name| {
            const lib_variant = comptime (std.meta.stringToEnum(Options.LibVariant, lib_variant_name) orelse unreachable);
            const lib = std.Build.Step.Compile.create(b, .{
                .name = lib_variant_name,
                .kind = .lib,
                .linkage = sub_linkage,
                .version = if (lib_variant == .c) .{
                    .major = 6,
                    .minor = 0,
                    .patch = 0,
                } else null,
                .root_module = .{
                    .target = target,
                    .optimize = optimize,
                    .root_source_file = b.path("lib/nulibc.zig"),
                },
            });

            lib.no_builtin = true;

            lib.step.dependOn(&hdrgen_step.step);

            lib.installHeadersDirectory(.{ .generated = .{
                .file = &include_wf.generated_directory,
            } }, ".", .{});

            lib.root_module.addOptions("options", (Options{
                .strict_dealloc = strict_dealloc,
                .target = null,
                .lib_variant = lib_variant,
            }).make(b));

            if (sub_linkage == linkage) b.installArtifact(lib);

            _ = libdir_wf.addCopyFile(lib.getEmittedBin(), lib.out_lib_filename);
        }
    }

    const ldso = b.addSharedLibrary(.{
        .name = b.fmt("ld-{s}-{s}", .{ @tagName(target.result.os.tag), @tagName(target.result.cpu.arch) }),
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("startup/ldso.zig"),
    });

    b.installArtifact(ldso);
    _ = libdir_wf.addCopyFile(ldso.getEmittedBin(), ldso.out_lib_filename);

    if (target.result.os.tag == .linux) {
        const Scrt1 = b.addObject(.{
            .name = "Scrt1",
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("startup/crt1.zig"),
        });

        _ = libdir_wf.addCopyFile(Scrt1.getEmittedBin(), "Scrt1.o");

        b.getInstallStep().dependOn(&b.addInstallArtifact(Scrt1, .{
            .dest_dir = .{
                .override = .lib,
            },
        }).step);

        const crt1 = b.addObject(.{
            .name = "crt1",
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("startup/crt1.zig"),
        });

        _ = libdir_wf.addCopyFile(crt1.getEmittedBin(), "crt1.o");

        b.getInstallStep().dependOn(&b.addInstallArtifact(crt1, .{
            .dest_dir = .{
                .override = .lib,
            },
        }).step);

        const crti = b.addObject(.{
            .name = "crti",
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("startup/crti.zig"),
        });

        _ = libdir_wf.addCopyFile(crti.getEmittedBin(), "crti.o");

        b.getInstallStep().dependOn(&b.addInstallArtifact(crti, .{
            .dest_dir = .{
                .override = .lib,
            },
        }).step);

        const crtn = b.addObject(.{
            .name = "crtn",
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("startup/crtn.zig"),
        });

        _ = libdir_wf.addCopyFile(crtn.getEmittedBin(), "crtn.o");

        b.getInstallStep().dependOn(&b.addInstallArtifact(crtn, .{
            .dest_dir = .{
                .override = .lib,
            },
        }).step);
    }

    const libc_install = LibCInstallStep.create(b, .{
        .crt_dir = libdir_wf.getDirectory(),
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
                    .linkage = linkage,
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

                test_exec.linkLibC();

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
