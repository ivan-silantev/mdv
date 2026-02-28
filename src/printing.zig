const std = @import("std");
const builtin = @import("builtin");
const renderer = @import("mdv_renderer");

fn getPrintTempDir(allocator: std.mem.Allocator) ![]u8 {
    const env_names = if (builtin.os.tag == .windows)
        [_][]const u8{ "TEMP", "TMP" }
    else
        [_][]const u8{"TMPDIR"};

    for (env_names) |name| {
        if (std.process.getEnvVarOwned(allocator, name)) |value| {
            if (value.len > 0) return value;
            allocator.free(value);
        } else |_| {}
    }

    if (builtin.os.tag == .windows) {
        return allocator.dupe(u8, ".");
    }

    return allocator.dupe(u8, "/tmp");
}

fn buildPrintTempPath(allocator: std.mem.Allocator, temp_dir: []const u8, nonce: u64) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "mdv-print-{d}-{x}.txt", .{ std.time.timestamp(), nonce });
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ temp_dir, filename });
}

fn createPrintTempPath(allocator: std.mem.Allocator) ![]u8 {
    const temp_dir = try getPrintTempDir(allocator);
    defer allocator.free(temp_dir);
    return buildPrintTempPath(allocator, temp_dir, std.crypto.random.int(u64));
}

pub fn printRenderedDocument(allocator: std.mem.Allocator, content: []const u8, size: renderer.Size) !void {
    const tmp_path = try createPrintTempPath(allocator);
    defer allocator.free(tmp_path);
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    {
        var tmp_file = try std.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
        defer tmp_file.close();
        var tmp_writer = tmp_file.writer(&.{});
        try renderer.renderMarkdown(allocator, &tmp_writer.interface, content, size, false);
    }

    if (builtin.os.tag == .windows) {
        var child = std.process.Child.init(&.{
            "powershell",
            "-NoProfile",
            "-Command",
            "Start-Process -FilePath $args[0] -Verb Print -Wait",
            tmp_path,
        }, allocator);
        _ = try child.spawnAndWait();
        return;
    }

    if (builtin.os.tag == .macos) {
        const script =
            "on run argv\n" ++
            "set docPath to POSIX file (item 1 of argv)\n" ++
            "tell application \"TextEdit\"\n" ++
            "open docPath\n" ++
            "activate\n" ++
            "end tell\n" ++
            "delay 0.4\n" ++
            "tell application \"System Events\"\n" ++
            "keystroke \"p\" using command down\n" ++
            "end tell\n" ++
            "end run\n";

        var child = std.process.Child.init(&.{
            "osascript",
            "-e",
            script,
            tmp_path,
        }, allocator);
        _ = try child.spawnAndWait();
        return;
    }

    var child = std.process.Child.init(&.{ "lp", tmp_path }, allocator);
    _ = try child.spawnAndWait();
}

test "buildPrintTempPath creates a path in the temp directory" {
    const path = try buildPrintTempPath(std.testing.allocator, "/tmp/mdv-test", 0xabc);
    defer std.testing.allocator.free(path);

    try std.testing.expect(std.mem.startsWith(u8, path, "/tmp/mdv-test"));
    try std.testing.expect(std.mem.endsWith(u8, path, "-abc.txt"));
}
