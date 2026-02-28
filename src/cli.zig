const std = @import("std");
const builtin = @import("builtin");
const renderer = @import("mdv_renderer");

pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const red = "\x1b[31m";

pub const CliOptions = struct {
    filename: []const u8,
    print_rendered: bool,
    render_html: bool,
};

pub fn style(enabled: bool, value: []const u8) []const u8 {
    return if (enabled) value else "";
}

pub fn printUsage(writer: anytype, program_name: []const u8, use_color: bool) !void {
    try writer.writeByte('\n');
    try writer.writeAll("  ");
    try writer.writeAll(style(use_color, bold));
    try writer.writeAll("mdv");
    try writer.writeAll(style(use_color, reset));
    try writer.writeAll(" - A simple terminal markdown viewer\n\n");
    try writer.writeAll("  Usage: ");
    try writer.writeAll(program_name);
    try writer.writeAll(" [--html] [-p] <file.md>\n");
    try writer.writeAll("  Options:\n");
    try writer.writeAll("    --html  Render markdown as HTML\n");
    try writer.writeAll("    -p      Send rendered terminal output to the system printer\n");
}

pub fn parseArgs(args: []const []const u8) !CliOptions {
    var filename: ?[]const u8 = null;
    var print_rendered = false;
    var render_html = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--html")) {
            render_html = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-p")) {
            print_rendered = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.ShowUsage;
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            return error.InvalidArgument;
        }

        if (filename != null) {
            return error.InvalidArgument;
        }

        filename = arg;
    }

    return .{
        .filename = filename orelse return error.ShowUsage,
        .print_rendered = print_rendered,
        .render_html = render_html,
    };
}
