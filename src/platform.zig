const std = @import("std");
const builtin = @import("builtin");
const renderer = @import("mdv_renderer");
const posix = std.posix;
const windows = std.os.windows;

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

    var ws: posix.winsize = .{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };
    const rc = posix.system.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(rc) != .SUCCESS or ws.col == 0 or ws.row == 0) return fallback;

    return .{
        .cols = ws.col,
        .rows = ws.row,
    };
}
