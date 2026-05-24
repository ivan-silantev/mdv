const std = @import("std");
const builtin = @import("builtin");
const renderer = @import("mdv_renderer");

const c = if (builtin.os.tag == .windows or builtin.os.tag == .linux)
    struct {}
else
    @cImport({
        @cInclude("sys/ioctl.h");
        @cInclude("unistd.h");
    });

pub fn getTerminalSize() renderer.Size {
    const fallback = renderer.Size{ .cols = 80, .rows = 24 };

    if (builtin.os.tag == .windows or builtin.os.tag == .linux) return fallback;

    var ws = std.mem.zeroes(c.struct_winsize);
    const rc = c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws);
    if (rc != 0 or ws.ws_col == 0 or ws.ws_row == 0) return fallback;

    return .{
        .cols = ws.ws_col,
        .rows = ws.ws_row,
    };
}
