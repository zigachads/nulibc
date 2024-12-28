// Based on the Zig implementation of "lib/std/start.zig" which is under
// the MIT license.
// Original source: https://github.com/ziglang/zig/blob/7d0087707634028308d3a870883249bfa59d94b8/lib/std/start.zig

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const native_arch = builtin.cpu.arch;
const native_os = builtin.os.tag;
const start_sym_name = if (native_arch.isMIPS()) "__start" else "_start";

pub const __nulibc_start_main = @extern(?*const fn (argc: usize, argv: [*]const [*:0]const u8, envp: [*]const [*:0]const u8, envp_count: usize) callconv(.C) noreturn, .{
    .name = "__nulibc_start_main",
});

pub fn _start() callconv(.naked) noreturn {
    asm volatile (switch (native_arch) {
            .arc => ".cfi_undefined blink",
            .aarch64, .aarch64_be => ".cfi_undefined lr",
            .csky => ".cfi_undefined lr",
            .hexagon => ".cfi_undefined r31",
            .loongarch32, .loongarch64 => ".cfi_undefined 1",
            .m68k => ".cfi_undefined pc",
            .mips, .mipsel, .mips64, .mips64el => ".cfi_undefined $ra",
            .powerpc, .powerpcle, .powerpc64, .powerpc64le => ".cfi_undefined lr",
            .riscv32, .riscv64 => ".cfi_undefined ra",
            .s390x => ".cfi_undefined %%r14",
            .sparc, .sparc64 => ".cfi_undefined %%i7",
            .x86 => ".cfi_undefined %%eip",
            .x86_64 => ".cfi_undefined %%rip",
            else => @compileError("unsupported arch"),
        });

    asm volatile (switch (native_arch) {
            .x86_64 =>
            \\ xorl %%ebp, %%ebp
            \\ movq %%rsp, %%rdi
            \\ andq $-16, %%rsp
            \\ callq %[posixCallMainAndExit:P]
            ,
            .x86 =>
            \\ xorl %%ebp, %%ebp
            \\ movl %%esp, %%eax
            \\ andl $-16, %%esp
            \\ subl $12, %%esp
            \\ pushl %%eax
            \\ calll %[posixCallMainAndExit:P]
            ,
            .aarch64, .aarch64_be =>
            \\ mov fp, #0
            \\ mov lr, #0
            \\ mov x0, sp
            \\ and sp, x0, #-16
            \\ b %[posixCallMainAndExit]
            ,
            .arc =>
            // The `arc` tag currently means ARC v1 and v2, which have an unusually low stack
            // alignment requirement. ARC v3 increases it from 4 to 16, but we don't support v3 yet.
            \\ mov fp, 0
            \\ mov blink, 0
            \\ mov r0, sp
            \\ and sp, sp, -4
            \\ b %[posixCallMainAndExit]
            ,
            .arm, .armeb, .thumb, .thumbeb =>
            // Note that this code must work for Thumb-1.
            // r7 = FP (local), r11 = FP (unwind)
            \\ movs v1, #0
            \\ mov r7, v1
            \\ mov r11, v1
            \\ mov lr, v1
            \\ mov a1, sp
            \\ subs v1, #16
            \\ ands v1, a1
            \\ mov sp, v1
            \\ b %[posixCallMainAndExit]
            ,
            .csky =>
            // The CSKY ABI assumes that `gb` is set to the address of the GOT in order for
            // position-independent code to work. We depend on this in `std.os.linux.pie` to locate
            // `_DYNAMIC` as well.
            // r8 = FP
            \\ grs t0, 1f
            \\ 1:
            \\ lrw gb, 1b@GOTPC
            \\ addu gb, t0
            \\ movi r8, 0
            \\ movi lr, 0
            \\ mov a0, sp
            \\ andi sp, sp, -8
            \\ jmpi %[posixCallMainAndExit]
            ,
            .hexagon =>
            // r29 = SP, r30 = FP, r31 = LR
            \\ r30 = #0
            \\ r31 = #0
            \\ r0 = r29
            \\ r29 = and(r29, #-16)
            \\ memw(r29 + #-8) = r29
            \\ r29 = add(r29, #-8)
            \\ call %[posixCallMainAndExit]
            ,
            .loongarch32, .loongarch64 =>
            \\ move $fp, $zero
            \\ move $ra, $zero
            \\ move $a0, $sp
            \\ bstrins.d $sp, $zero, 3, 0
            \\ b %[posixCallMainAndExit]
            ,
            .riscv32, .riscv64 =>
            \\ li fp, 0
            \\ li ra, 0
            \\ mv a0, sp
            \\ andi sp, sp, -16
            \\ tail %[posixCallMainAndExit]@plt
            ,
            .m68k =>
            // Note that the - 8 is needed because pc in the jsr instruction points into the middle
            // of the jsr instruction. (The lea is 6 bytes, the jsr is 4 bytes.)
            \\ suba.l %%fp, %%fp
            \\ move.l %%sp, -(%%sp)
            \\ lea %[posixCallMainAndExit] - . - 8, %%a0
            \\ jsr (%%pc, %%a0)
            ,
            .mips, .mipsel =>
            \\ move $fp, $0
            \\ bal 1f
            \\ .gpword .
            \\ .gpword %[posixCallMainAndExit]
            \\ 1:
            // The `gp` register on MIPS serves a similar purpose to `r2` (ToC pointer) on PPC64.
            \\ lw $gp, 0($ra)
            \\ subu $gp, $ra, $gp
            \\ lw $25, 4($ra)
            \\ addu $25, $25, $gp
            \\ move $ra, $0
            \\ move $a0, $sp
            \\ and $sp, -8
            \\ subu $sp, $sp, 16
            \\ jalr $25
            ,
            .mips64, .mips64el =>
            \\ move $fp, $0
            // This is needed because early MIPS versions don't support misaligned loads. Without
            // this directive, the hidden `nop` inserted to fill the delay slot after `bal` would
            // cause the two doublewords to be aligned to 4 bytes instead of 8.
            \\ .balign 8
            \\ bal 1f
            \\ .gpdword .
            \\ .gpdword %[posixCallMainAndExit]
            \\ 1:
            // The `gp` register on MIPS serves a similar purpose to `r2` (ToC pointer) on PPC64.
            \\ ld $gp, 0($ra)
            \\ dsubu $gp, $ra, $gp
            \\ ld $25, 8($ra)
            \\ daddu $25, $25, $gp
            \\ move $ra, $0
            \\ move $a0, $sp
            \\ and $sp, -16
            \\ dsubu $sp, $sp, 16
            \\ jalr $25
            ,
            .powerpc, .powerpcle =>
            // Set up the initial stack frame, and clear the back chain pointer.
            // r1 = SP, r31 = FP
            \\ mr 3, 1
            \\ clrrwi 1, 1, 4
            \\ li 0, 0
            \\ stwu 1, -16(1)
            \\ stw 0, 0(1)
            \\ li 31, 0
            \\ mtlr 0
            \\ b %[posixCallMainAndExit]
            ,
            .powerpc64, .powerpc64le =>
            // Set up the ToC and initial stack frame, and clear the back chain pointer.
            // r1 = SP, r2 = ToC, r31 = FP
            \\ addis 2, 12, .TOC. - %[_start]@ha
            \\ addi 2, 2, .TOC. - %[_start]@l
            \\ mr 3, 1
            \\ clrrdi 1, 1, 4
            \\ li 0, 0
            \\ stdu 0, -32(1)
            \\ li 31, 0
            \\ mtlr 0
            \\ b %[posixCallMainAndExit]
            \\ nop
            ,
            .s390x =>
            // Set up the stack frame (register save area and cleared back-chain slot).
            // r11 = FP, r14 = LR, r15 = SP
            \\ lghi %%r11, 0
            \\ lghi %%r14, 0
            \\ lgr %%r2, %%r15
            \\ lghi %%r0, -16
            \\ ngr %%r15, %%r0
            \\ aghi %%r15, -160
            \\ lghi %%r0, 0
            \\ stg  %%r0, 0(%%r15)
            \\ jg %[posixCallMainAndExit]
            ,
            .sparc =>
            // argc is stored after a register window (16 registers * 4 bytes).
            // i7 = LR
            \\ mov %%g0, %%fp
            \\ mov %%g0, %%i7
            \\ add %%sp, 64, %%o0
            \\ and %%sp, -8, %%sp
            \\ ba,a %[posixCallMainAndExit]
            ,
            .sparc64 =>
            // argc is stored after a register window (16 registers * 8 bytes) plus the stack bias
            // (2047 bytes).
            // i7 = LR
            \\ mov %%g0, %%fp
            \\ mov %%g0, %%i7
            \\ add %%sp, 2175, %%o0
            \\ add %%sp, 2047, %%sp
            \\ and %%sp, -16, %%sp
            \\ sub %%sp, 2047, %%sp
            \\ ba,a %[posixCallMainAndExit]
            ,
            else => @compileError("unsupported arch"),
        }
        :
        : [_start] "X" (&_start),
          [posixCallMainAndExit] "X" (&posixCallMainAndExit),
    );
}

pub fn posixCallMainAndExit(argc_argv_ptr: [*]usize) callconv(.C) noreturn {
    @setRuntimeSafety(false);
    @disableInstrumentation();

    const argc = argc_argv_ptr[0];
    const argv = @as([*][*:0]u8, @ptrCast(argc_argv_ptr + 1));

    const envp_optional: [*:null]?[*:0]u8 = @ptrCast(@alignCast(argv + argc + 1));
    var envp_count: usize = 0;
    while (envp_optional[envp_count]) |_| : (envp_count += 1) {}
    const envp = @as([*][*:0]u8, @ptrCast(envp_optional))[0..envp_count];

    if (__nulibc_start_main) |f| {
        f(argc, argv, envp.ptr, envp_count);
    }

    std.debug.panic("Could not load symbol __nulibc_start_main", .{});
}

comptime {
    @export(&_start, .{ .name = start_sym_name });
}
