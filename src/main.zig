const std = @import("std");
const renderer = @import("mdv_renderer");
const cli = @import("cli");
const platform = @import("platform");
const printing = @import("printing");

pub fn main(init: std.process.Init) !void {
    const size = platform.getTerminalSize();

    var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_writer.interface;
    const allocator = init.gpa;
    const use_color = try renderer.terminalColorsEnabled(allocator);

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const options = cli.parseArgs(args) catch |err| switch (err) {
        error.ShowUsage => {
            try cli.printUsage(stdout, args[0], use_color);
            return;
        },
        error.InvalidArgument => {
            try stdout.writeAll(cli.style(use_color, cli.red));
            try stdout.writeAll("Invalid arguments.");
            try stdout.writeAll(cli.style(use_color, cli.reset));
            try stdout.writeByte('\n');
            try cli.printUsage(stdout, args[0], use_color);
            return;
        },
    };

    const content = if (options.read_stdin) try readStdinAlloc(init.io, allocator) else try readFileAlloc(init.io, allocator, stdout, use_color, options.filename);
    defer allocator.free(content);

    if (options.render_html) {
        renderer.renderHtmlMarkdown(allocator, stdout, content) catch |err| {
            try stdout.print("{s}Render failed: {t}{s}\n", .{ cli.style(use_color, cli.red), err, cli.style(use_color, cli.reset) });
            std.process.exit(1);
        };
        return;
    }

    renderer.renderMarkdown(allocator, stdout, content, size, use_color) catch |err| {
        try stdout.print("{s}Render failed: {t}{s}\n", .{ cli.style(use_color, cli.red), err, cli.style(use_color, cli.reset) });
        std.process.exit(1);
    };

    if (options.print_rendered) {
        printing.printRenderedDocument(allocator, content, size) catch |err| {
            try stdout.print("{s}Print failed: {t}{s}\n", .{ cli.style(use_color, cli.red), err, cli.style(use_color, cli.reset) });
            std.process.exit(1);
        };
    }
}

fn readFileAlloc(io: std.Io, allocator: std.mem.Allocator, stdout: anytype, use_color: bool, filename: []const u8) ![]u8 {
    var file = std.Io.Dir.cwd().openFile(io, filename, .{}) catch |err| {
        try stdout.print("{s}Error opening file '{s}': {t}{s}\n", .{ cli.style(use_color, cli.red), filename, err, cli.style(use_color, cli.reset) });
        std.process.exit(1);
    };
    defer file.close(io);

    const len = try file.length(io);
    const content = try allocator.alloc(u8, @intCast(len));
    _ = try file.readPositionalAll(io, content, 0);
    return content;
}

fn readStdinAlloc(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    return stdin_reader.interface.allocRemaining(allocator, .limited(64 * 1024 * 1024));
}
