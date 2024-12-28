// Based on the Zig implementation of "lib/std/start.zig" which is under
// the MIT license.
// Original source: https://github.com/ziglang/zig/blob/7d0087707634028308d3a870883249bfa59d94b8/lib/std/start.zig

const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const internal = @import("internal.zig");
const assert = std.debug.assert;

const native_arch = builtin.cpu.arch;
const native_os = builtin.os.tag;

const MainFunc = ?*const fn (argc: usize, argv: [*]const [*:0]const u8, envp: [*]const [*:0]const u8) callconv(.C) u8;

pub const main: MainFunc = if (options.use_exports) @extern(MainFunc, .{
    .name = "main",
}) else null;

pub fn startMain(argc: usize, argv: [*][*:0]u8, envp: [*][*:0]u8, envp_count: usize) callconv(.C) noreturn {
    @setRuntimeSafety(false);
    @disableInstrumentation();

    if (native_os == .linux) {
        // Find the beginning of the auxiliary vector
        const auxv: [*]std.elf.Auxv = @ptrCast(@alignCast(envp + envp_count + 1));

        var at_hwcap: usize = 0;
        const phdrs = init: {
            var i: usize = 0;
            var at_phdr: usize = 0;
            var at_phnum: usize = 0;
            while (auxv[i].a_type != std.elf.AT_NULL) : (i += 1) {
                switch (auxv[i].a_type) {
                    std.elf.AT_PHNUM => at_phnum = auxv[i].a_un.a_val,
                    std.elf.AT_PHDR => at_phdr = auxv[i].a_un.a_val,
                    std.elf.AT_HWCAP => at_hwcap = auxv[i].a_un.a_val,
                    else => continue,
                }
            }
            break :init @as([*]std.elf.Phdr, @ptrFromInt(at_phdr))[0..at_phnum];
        };

        // Apply the initial relocations as early as possible in the startup process. We cannot
        // make calls yet on some architectures (e.g. MIPS) *because* they haven't been applied yet,
        // so this must be fully inlined.
        if (builtin.position_independent_executable) {
            @call(.always_inline, std.os.linux.pie.relocate, .{phdrs});
        }

        // This must be done after PIE relocations have been applied or we may crash
        // while trying to access the global variable (happens on MIPS at least).
        std.os.linux.elf_aux_maybe = auxv;

        if (!builtin.single_threaded) {
            // ARMv6 targets (and earlier) have no support for TLS in hardware.
            // FIXME: Elide the check for targets >= ARMv7 when the target feature API
            // becomes less verbose (and more usable).
            if (comptime native_arch.isARM()) {
                if (at_hwcap & std.os.linux.HWCAP.TLS == 0) {
                    // FIXME: Make __aeabi_read_tp call the kernel helper kuser_get_tls
                    // For the time being use a simple trap instead of a @panic call to
                    // keep the binary bloat under control.
                    @trap();
                }
            }

            // Initialize the TLS area.
            std.os.linux.tls.initStatic(phdrs);
        }

        // The way Linux executables represent stack size is via the PT_GNU_STACK
        // program header. However the kernel does not recognize it; it always gives 8 MiB.
        // Here we look for the stack size in our program headers and use setrlimit
        // to ask for more stack space.
        expandStackSize(phdrs);

        const opt_init_array_start = @extern([*]*const fn () callconv(.c) void, .{
            .name = "__init_array_start",
            .linkage = .weak,
        });
        const opt_init_array_end = @extern([*]*const fn () callconv(.c) void, .{
            .name = "__init_array_end",
            .linkage = .weak,
        });
        if (opt_init_array_start) |init_array_start| {
            const init_array_end = opt_init_array_end.?;
            const slice = init_array_start[0 .. init_array_end - init_array_start];
            for (slice) |func| func();
        }
    }

    const r = callMainWithArgs(argc, argv, envp[0..envp_count]);

    if (options.strict_dealloc) {
        if (internal.gpa.deinit() == .leak) {
            internal.log.err("leak detected", .{});
        }
    }

    std.posix.exit(r);
}

fn expandStackSize(phdrs: []std.elf.Phdr) void {
    for (phdrs) |*phdr| {
        switch (phdr.p_type) {
            std.elf.PT_GNU_STACK => {
                if (phdr.p_memsz == 0) break;
                assert(phdr.p_memsz % std.heap.pageSize() == 0);

                // Silently fail if we are unable to get limits.
                const limits = std.posix.getrlimit(.STACK) catch break;

                // Clamp to limits.max .
                const wanted_stack_size = @min(phdr.p_memsz, limits.max);

                if (wanted_stack_size > limits.cur) {
                    std.posix.setrlimit(.STACK, .{
                        .cur = wanted_stack_size,
                        .max = limits.max,
                    }) catch {
                        // Because we could not increase the stack size to the upper bound,
                        // depending on what happens at runtime, a stack overflow may occur.
                        // However it would cause a segmentation fault, thanks to stack probing,
                        // so we do not have a memory safety issue here.
                        // This is intentional silent failure.
                        // This logic should be revisited when the following issues are addressed:
                        // https://github.com/ziglang/zig/issues/157
                        // https://github.com/ziglang/zig/issues/1006
                    };
                }
                break;
            },
            else => {},
        }
    }
}

inline fn callMainWithArgs(argc: usize, argv: [*][*:0]u8, envp: [][*:0]u8) u8 {
    std.os.argv = argv[0..argc];
    std.os.environ = envp;

    std.debug.maybeEnableSegfaultHandler();
    maybeIgnoreSigpipe();

    if (main) |f| {
        return f(argc, argv, envp.ptr);
    }

    std.debug.panic("Cannot load symbol main", .{});
}

fn maybeIgnoreSigpipe() void {
    const have_sigpipe_support = switch (builtin.os.tag) {
        .linux,
        .plan9,
        .solaris,
        .netbsd,
        .openbsd,
        .haiku,
        .macos,
        .ios,
        .watchos,
        .tvos,
        .visionos,
        .dragonfly,
        .freebsd,
        => true,

        else => false,
    };

    if (have_sigpipe_support and !std.options.keep_sigpipe) {
        const posix = std.posix;
        const act: posix.Sigaction = .{
            // Set handler to a noop function instead of `SIG.IGN` to prevent
            // leaking signal disposition to a child process.
            .handler = .{ .handler = noopSigHandler },
            .mask = posix.empty_sigset,
            .flags = 0,
        };
        posix.sigaction(posix.SIG.PIPE, &act, null);
    }
}

fn noopSigHandler(_: i32) callconv(.c) void {}

comptime {
    if (options.use_exports) {
        @export(&startMain, .{ .name = "__nulibc_start_main" });
    }
}
