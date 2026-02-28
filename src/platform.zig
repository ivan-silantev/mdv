const std = @import("std");
const builtin = @import("builtin");
const renderer = @import("mdv_renderer");
const windows = std.os.windows;

const c = if (builtin.os.tag == .windows)
    struct {}
else
    @cImport({
        @cInclude("sys/ioctl.h");
        @cInclude("unistd.h");
    });

pub fn getTerminalSize() renderer.Size {
    const fallback = renderer.Size{ .cols = 80, .rows = 24 };

    if (builtin.os.tag == .windows) {
        const handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return fallback;
        var info: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (windows.kernel32.GetConsoleScreenBufferInfo(handle, &info) == windows.FALSE) {
            return fallback;
        }

        const width: i32 = @as(i32, info.srWindow.Right) - @as(i32, info.srWindow.Left) + 1;
        const height: i32 = @as(i32, info.srWindow.Bottom) - @as(i32, info.srWindow.Top) + 1;
        if (width <= 0 or height <= 0) return fallback;

        return .{
            .cols = @intCast(width),
            .rows = @intCast(height),
        };
    }

    var ws = std.mem.zeroes(c.struct_winsize);
    const rc = c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws);
    if (rc != 0 or ws.ws_col == 0 or ws.ws_row == 0) return fallback;

    return .{
        .cols = ws.ws_col,
        .rows = ws.ws_row,
    };
}
