const std = @import("std");
const builtin = @import("builtin");
const renderer = @import("mdv_renderer");

pub fn printRenderedDocument(allocator: std.mem.Allocator, content: []const u8, size: renderer.Size) !void {
    _ = allocator; _ = content; _ = size;
}
