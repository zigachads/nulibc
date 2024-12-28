const std = @import("std");
const options = @import("options");

pub fn getauxval(t: c_ulong) callconv(.C) c_ulong {
    const auxv = std.os.linux.elf_aux_maybe orelse return 0;
    var i: usize = 0;
    while (auxv[i].a_type != std.elf.AT_NULL) : (i += 1) {
        if (auxv[i].a_type == t)
            return auxv[i].a_un.a_val;
    }
    return 0;
}

comptime {
    if (options.use_exports) {
        @export(&getauxval, .{ .name = "getauxval" });
    }
}
