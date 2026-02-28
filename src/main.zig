const std = @import("std");
const renderer = @import("mdv_renderer");
const cli = @import("cli");
const platform = @import("platform");
const printing = @import("printing");

pub fn main() !void {
    const size = platform.getTerminalSize();

    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const use_color = try renderer.terminalColorsEnabled(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
        else => return err,
    };

    var file = std.fs.cwd().openFile(options.filename, .{}) catch |err| {
        try stdout.print("{s}Error opening file '{s}': {}{s}\n", .{ cli.style(use_color, cli.red), options.filename, err, cli.style(use_color, cli.reset) });
        return;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(content);

    if (options.render_html) {
        renderer.renderHtmlMarkdown(allocator, stdout, content) catch |err| {
            try stdout.print("{s}Render failed: {}{s}\n", .{ cli.style(use_color, cli.red), err, cli.style(use_color, cli.reset) });
            std.process.exit(1);
        };
        return;
    }

    renderer.renderMarkdown(allocator, stdout, content, size, use_color) catch |err| {
        try stdout.print("{s}Render failed: {}{s}\n", .{ cli.style(use_color, cli.red), err, cli.style(use_color, cli.reset) });
        std.process.exit(1);
    };

    if (options.print_rendered) {
        printing.printRenderedDocument(allocator, content, size) catch |err| {
            try stdout.print("{s}Print failed: {}{s}\n", .{ cli.style(use_color, cli.red), err, cli.style(use_color, cli.reset) });
            std.process.exit(1);
        };
    }
}
