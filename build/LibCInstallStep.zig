const std = @import("std");
const LibCInstallStep = @This();
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    include_dir: ?LazyPath = null,
    sys_include_dir: ?LazyPath = null,
    crt_dir: ?LazyPath = null,
    msvc_lib_dir: ?LazyPath = null,
    kernel32_lib_dir: ?LazyPath = null,
    gcc_dir: ?LazyPath = null,
};

step: std.Build.Step,
generated_file: std.Build.GeneratedFile,
include_dir: ?LazyPath,
sys_include_dir: ?LazyPath,
crt_dir: ?LazyPath = null,
msvc_lib_dir: ?LazyPath = null,
kernel32_lib_dir: ?LazyPath = null,
gcc_dir: ?LazyPath = null,

pub fn create(b: *std.Build, options: Options) *LibCInstallStep {
    const self = b.allocator.create(LibCInstallStep) catch @panic("OOM");

    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "libc install",
            .owner = b,
            .makeFn = make,
        }),
        .generated_file = .{
            .step = &self.step,
        },
        .include_dir = options.include_dir,
        .sys_include_dir = options.sys_include_dir,
        .crt_dir = options.crt_dir,
        .msvc_lib_dir = options.msvc_lib_dir,
        .kernel32_lib_dir = options.kernel32_lib_dir,
        .gcc_dir = options.gcc_dir,
    };

    if (options.include_dir) |include_dir|
        include_dir.addStepDependencies(&self.step);

    if (options.sys_include_dir) |sys_include_dir|
        sys_include_dir.addStepDependencies(&self.step);

    if (options.crt_dir) |crt_dir|
        crt_dir.addStepDependencies(&self.step);

    if (options.msvc_lib_dir) |msvc_lib_dir|
        msvc_lib_dir.addStepDependencies(&self.step);

    if (options.kernel32_lib_dir) |kernel32_lib_dir|
        kernel32_lib_dir.addStepDependencies(&self.step);

    if (options.gcc_dir) |gcc_dir|
        gcc_dir.addStepDependencies(&self.step);
    return self;
}

fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    const b = step.owner;
    const arena = b.allocator;
    const self: *LibCInstallStep = @fieldParentPtr("step", step);

    step.clearWatchInputs();

    var man = b.graph.cache.obtain();
    defer man.deinit();

    _ = if (self.include_dir) |v| try step.addDirectoryWatchInput(v);
    _ = if (self.sys_include_dir) |v| try step.addDirectoryWatchInput(v);
    _ = if (self.crt_dir) |v| try step.addDirectoryWatchInput(v);
    _ = if (self.msvc_lib_dir) |v| try step.addDirectoryWatchInput(v);
    _ = if (self.kernel32_lib_dir) |v| try step.addDirectoryWatchInput(v);
    _ = if (self.gcc_dir) |v| try step.addDirectoryWatchInput(v);

    const include_dir = if (self.include_dir) |include_dir| include_dir.getPath2(b, step) else null;
    man.hash.addOptionalBytes(include_dir);

    const sys_include_dir = if (self.sys_include_dir) |sys_include_dir| sys_include_dir.getPath2(b, step) else null;
    man.hash.addOptionalBytes(sys_include_dir);

    const crt_dir = if (self.crt_dir) |crt_dir| crt_dir.getPath2(b, step) else null;
    man.hash.addOptionalBytes(crt_dir);

    const msvc_lib_dir = if (self.msvc_lib_dir) |msvc_lib_dir| msvc_lib_dir.getPath2(b, step) else null;
    man.hash.addOptionalBytes(msvc_lib_dir);

    const kernel32_lib_dir = if (self.kernel32_lib_dir) |kernel32_lib_dir| kernel32_lib_dir.getPath2(b, step) else null;
    man.hash.addOptionalBytes(kernel32_lib_dir);

    const gcc_dir = if (self.gcc_dir) |gcc_dir| gcc_dir.getPath2(b, step) else null;
    man.hash.addOptionalBytes(gcc_dir);

    if (try step.cacheHit(&man)) {
        const digest = man.final();
        self.generated_file.path = try b.cache_root.join(arena, &.{ "o", &digest });
        step.result_cached = true;
        return;
    }

    const digest = man.final();
    const cache_path = "o" ++ std.fs.path.sep_str ++ digest;

    self.generated_file.path = try b.cache_root.join(arena, &.{ "o", &digest });

    var cache_file = b.cache_root.handle.createFile(cache_path, .{}) catch |err| {
        return step.fail("unable to create file path '{}{s}': {s}", .{
            b.cache_root, cache_path, @errorName(err),
        });
    };
    defer cache_file.close();

    const libc = std.zig.LibCInstallation{
        .include_dir = include_dir,
        .sys_include_dir = sys_include_dir,
        .crt_dir = crt_dir,
        .msvc_lib_dir = msvc_lib_dir,
        .kernel32_lib_dir = kernel32_lib_dir,
        .gcc_dir = gcc_dir,
    };

    try libc.render(cache_file.writer());
    try step.writeManifest(&man);
}
