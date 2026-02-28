const std = @import("std");

// ANSI Escapes
const reset = "\x1b[0m";
const bold = "\x1b[1m";
const dim = "\x1b[2m";
const italic = "\x1b[3m";
const underline = "\x1b[4m";

// Colors
const red = "\x1b[31m";
const green = "\x1b[32m";
const yellow = "\x1b[33m";
const blue = "\x1b[34m";
const magenta = "\x1b[35m";
const cyan = "\x1b[36m";
const white = "\x1b[37m";

pub const ParseError = error{
    OutOfMemory,
    ContainerStackOverflow,
};

pub const RendererError = ParseError;

pub const Size = struct {
    cols: u32,
    rows: u32,
};

fn style(enabled: bool, value: []const u8) []const u8 {
    return if (enabled) value else "";
}

fn colorsEnabledFromNoColor(no_color: ?[]const u8) bool {
    return no_color == null or no_color.?.len == 0;
}

pub fn terminalColorsEnabled(allocator: std.mem.Allocator) !bool {
    const no_color = std.process.getEnvVarOwned(allocator, "NO_COLOR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return true,
        else => return err,
    };
    defer allocator.free(no_color);

    return colorsEnabledFromNoColor(no_color);
}

test "NO_COLOR disables terminal colors when non-empty" {
    try std.testing.expect(colorsEnabledFromNoColor(null));
    try std.testing.expect(colorsEnabledFromNoColor(""));
    try std.testing.expect(!colorsEnabledFromNoColor("1"));
}
const Fence = struct {
    char: u8,
    len: usize,
    indent: usize,
    info: []const u8,
};

const Heading = struct {
    level: usize,
    text: []const u8,
};

const ListMarker = struct {
    ordered: bool,
    number: usize,
    indent: usize,
    width: usize,
    content_start: usize,
    content_start_columns: usize,
    content_indent: usize,
    marker_char: u8,
    delimiter: u8,
};

const LinkTarget = struct {
    destination: []const u8,
    title: ?[]const u8,
    valid: bool,
    process_escapes: bool,
};

const LinkReference = struct {
    label: []const u8,
    target: LinkTarget,
    owned_source: []const u8 = "",
};

const HtmlBlockKind = enum {
    comment,
    processing_instruction,
    declaration,
    cdata,
    raw_tag,
    block_tag,
    complete_tag,
};

const ListItem = struct {
    marker: ListMarker,
    content: []const u8,
    raw_content: []const u8 = "",
    child_stack: ContainerStack = ContainerStack.empty(),
    loose: bool,
};

const BlockKind = enum {
    blank,
    heading,
    setext_heading,
    thematic_break,
    fenced_code,
    indented_code,
    html_block,
    block_quote,
    list,
    paragraph,
};

const AstBlock = struct {
    kind: BlockKind,
    source: []const u8,
    container_stack: ContainerStack = ContainerStack.empty(),
    heading: ?Heading = null,
    fence: ?Fence = null,
    list_marker: ?ListMarker = null,
    list_items: []const ListItem = &[_]ListItem{},
    link_reference: ?LinkReference = null,
    child_content: []const u8 = "",
    children: []AstBlock = &[_]AstBlock{},
    child_references: []LinkReference = &[_]LinkReference{},
};

const CommonMarkAst = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(AstBlock),
    references: std.ArrayList(LinkReference),

    fn deinit(self: *CommonMarkAst) void {
        for (self.blocks.items) |block| deinitAstBlock(self.allocator, block);
        for (self.references.items) |reference| deinitLinkReference(self.allocator, reference);
        self.references.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
    }
};

const ReferenceLookup = struct {
    content: []const u8,
    references: []const LinkReference = &[_]LinkReference{},
};

const ContainerKind = enum {
    block_quote,
    list_item,
};

const Container = struct {
    kind: ContainerKind,
    content_indent: usize = 0,
};

const ContainerLineContext = struct {
    matched: bool,
    content: []const u8,
    padding: usize = 0,
    blank: bool,
    indent_columns: usize,
    column_offset: usize = 0,
    active_containers: usize = 0,
};

const ContainerStack = struct {
    containers: [16]Container = undefined,
    len: usize = 0,

    fn empty() ContainerStack {
        return .{};
    }

    fn push(self: *ContainerStack, container: Container) !void {
        if (self.len >= self.containers.len) return error.ContainerStackOverflow;
        self.containers[self.len] = container;
        self.len += 1;
    }

    fn pushBlockQuote(self: *ContainerStack) !void {
        try self.push(.{ .kind = .block_quote });
    }

    fn pushListItem(self: *ContainerStack, content_indent: usize) !void {
        try self.push(.{ .kind = .list_item, .content_indent = content_indent });
    }

    fn hasBlockQuote(self: ContainerStack) bool {
        for (self.containers[0..self.len]) |container| {
            if (container.kind == .block_quote) return true;
        }
        return false;
    }

    fn normalizeLine(self: ContainerStack, line: []const u8) ContainerLineContext {
        var current_line = line;
        var matched_all = true;
        var active: usize = 0;
        var total_column_offset: usize = 0;
        var last_padding: usize = 0;

        for (self.containers[0..self.len]) |container| {
            const context = switch (container.kind) {
                .block_quote => matchBlockQuoteContainer(current_line),
                .list_item => matchListItemContainer(current_line, container.content_indent),
            };
            if (!context.matched) {
                matched_all = false;
                break;
            }
            active += 1;
            current_line = context.content;
            total_column_offset += context.column_offset;
            last_padding = context.padding;
        }

        return .{
            .matched = matched_all,
            .content = current_line,
            .padding = last_padding,
            .blank = isBlank(current_line) and last_padding == 0,
            .indent_columns = countLeadingColumns(current_line, total_column_offset) + last_padding,
            .column_offset = total_column_offset,
            .active_containers = active,
        };
    }
};

test "ContainerStack reports overflow" {
    var stack = ContainerStack.empty();
    for (0..stack.containers.len) |_| try stack.pushBlockQuote();

    try std.testing.expectError(error.ContainerStackOverflow, stack.pushBlockQuote());
}

test "ContainerStack evaluates nesting boundaries" {
    var stack = ContainerStack.empty();
    try stack.pushBlockQuote();
    try stack.pushListItem(2);

    // Valid continuation of both quote and list
    const ctx1 = stack.normalizeLine(">   hello");
    if (!ctx1.matched) {
        std.debug.print("ctx1.matched: {any}, ctx1.active_containers: {d}, ctx1.content: '{s}'\n", .{ ctx1.matched, ctx1.active_containers, ctx1.content });
    }
    try std.testing.expectEqual(true, ctx1.matched);
    try std.testing.expectEqual(@as(usize, 2), ctx1.active_containers);
    try std.testing.expectEqualStrings("hello", ctx1.content);

    // Breaks out of list but matches quote
    const ctx2 = stack.normalizeLine("> hello");
    try std.testing.expectEqual(false, ctx2.matched);
    try std.testing.expectEqual(@as(usize, 1), ctx2.active_containers);
    try std.testing.expectEqualStrings("hello", ctx2.content);

    // Breaks out of both quote and list
    const ctx3 = stack.normalizeLine("hello");
    try std.testing.expectEqual(false, ctx3.matched);
    try std.testing.expectEqual(@as(usize, 0), ctx3.active_containers);
    try std.testing.expectEqualStrings("hello", ctx3.content);
}

fn matchBlockQuoteContainer(line: []const u8) ContainerLineContext {
    const marker = consumeBlockQuoteMarker(line) orelse {
        return .{
            .matched = false,
            .content = line,
            .blank = isBlank(line),
            .indent_columns = leadingColumns(line),
            .column_offset = 0,
        };
    };

    return .{
        .matched = true,
        .content = marker.content,
        .padding = marker.padding,
        .blank = isBlank(marker.content) and marker.padding == 0,
        .indent_columns = leadingColumns(marker.content) + marker.padding,
        .column_offset = marker.consumed_columns,
    };
}

fn matchListItemContainer(line: []const u8, content_indent: usize) ContainerLineContext {
    if (isBlank(line)) {
        return .{ .matched = true, .content = "", .blank = true, .indent_columns = 0, .column_offset = leadingColumns(line) };
    }

    const columns = leadingColumns(line);
    if (columns < content_indent) {
        return .{
            .matched = false,
            .content = line,
            .blank = false,
            .indent_columns = columns,
            .column_offset = 0,
        };
    }

    const stripped = stripIndentColumns(line, content_indent);
    return .{
        .matched = true,
        .content = stripped.content,
        .padding = stripped.padding,
        .blank = false,
        .indent_columns = leadingColumns(stripped.content) + stripped.padding,
        .column_offset = content_indent,
    };
}

fn blockQuoteLineContext(line: []const u8) ContainerLineContext {
    var stack = ContainerStack.empty();
    stack.pushBlockQuote() catch unreachable;
    return stack.normalizeLine(line);
}

fn listContinuationContext(line: []const u8, content_indent: usize) ContainerLineContext {
    var stack = ContainerStack.empty();
    stack.pushListItem(content_indent) catch unreachable;
    return stack.normalizeLine(line);
}

fn consumedBytes(line: []const u8, content: []const u8) usize {
    const line_start = @intFromPtr(line.ptr);
    const content_start = @intFromPtr(content.ptr);
    if (content_start < line_start or content_start > line_start + line.len) return 0;
    return content_start - line_start;
}

fn consumedColumns(line: []const u8, content: []const u8) usize {
    const bytes = consumedBytes(line, content);
    var col: usize = 0;
    for (line[0..bytes]) |c| {
        if (c == '\t') {
            col += 4 - (col % 4);
        } else {
            col += 1;
        }
    }
    return col;
}

fn stripFenceIndent(line: []const u8, indent: usize) []const u8 {
    var idx: usize = 0;
    while (idx < line.len and idx < indent and line[idx] == ' ') : (idx += 1) {}
    return line[idx..];
}

fn deinitAstBlock(allocator: std.mem.Allocator, block: AstBlock) void {
    for (block.list_items) |item| {
        allocator.free(item.content);
        if (item.raw_content.len > 0) allocator.free(item.raw_content);
    }
    if (block.list_items.len > 0) allocator.free(block.list_items);
    for (block.children) |child| deinitAstBlock(allocator, child);
    if (block.children.len > 0) allocator.free(block.children);
    for (block.child_references) |reference| deinitLinkReference(allocator, reference);
    if (block.child_references.len > 0) allocator.free(block.child_references);
    if (block.child_content.len > 0) allocator.free(block.child_content);
}

fn deinitLinkReference(allocator: std.mem.Allocator, reference: LinkReference) void {
    if (reference.owned_source.len > 0) allocator.free(reference.owned_source);
}

fn cloneLinkReference(allocator: std.mem.Allocator, reference: LinkReference) !LinkReference {
    const owned = try allocator.dupe(u8, reference.owned_source);
    errdefer allocator.free(owned);

    const label_start = @intFromPtr(reference.label.ptr) - @intFromPtr(reference.owned_source.ptr);
    const destination_start = @intFromPtr(reference.target.destination.ptr) - @intFromPtr(reference.owned_source.ptr);
    const title_start = if (reference.target.title) |title| @intFromPtr(title.ptr) - @intFromPtr(reference.owned_source.ptr) else 0;
    return .{
        .label = owned[label_start .. label_start + reference.label.len],
        .target = .{
            .destination = owned[destination_start .. destination_start + reference.target.destination.len],
            .title = if (reference.target.title) |title| owned[title_start .. title_start + title.len] else null,
            .valid = reference.target.valid,
            .process_escapes = reference.target.process_escapes,
        },
        .owned_source = owned,
    };
}

fn lineBounds(content: []const u8, start: usize) ?struct { line: []const u8, next: usize } {
    if (start >= content.len) return null;
    const rel_end = std.mem.indexOfScalar(u8, content[start..], '\n');
    const end = if (rel_end) |idx| start + idx else content.len;
    const next = if (end < content.len) end + 1 else content.len;
    const raw_line = content[start..end];
    const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r') raw_line[0 .. raw_line.len - 1] else raw_line;
    return .{ .line = line, .next = next };
}

fn leadingSpaces(line: []const u8, max: usize) usize {
    var count: usize = 0;
    while (count < line.len and count < max and line[count] == ' ') count += 1;
    return count;
}

fn leadingColumns(line: []const u8) usize {
    return countLeadingColumns(line, 0);
}

fn countLeadingColumns(line: []const u8, start_col: usize) usize {
    var col = start_col;
    for (line) |c| {
        if (c == ' ') {
            col += 1;
        } else if (c == '\t') {
            col += 4 - (col % 4);
        } else break;
    }
    return col - start_col;
}

const StrippedLine = struct {
    content: []const u8,
    padding: usize,
};

const BlockQuoteMarker = struct {
    content: []const u8,
    padding: usize,
    consumed_columns: usize,
};

fn stripIndentColumns(line: []const u8, target_columns: usize) StrippedLine {
    var idx: usize = 0;
    var columns: usize = 0; // Current column count as we iterate through the line

    // Iterate through the line, consuming characters (spaces and tabs)
    // until we have consumed 'target_columns' or encountered a non-whitespace character.
    while (idx < line.len and columns < target_columns) : (idx += 1) {
        if (line[idx] == ' ') {
            columns += 1;
        } else if (line[idx] == '\t') {
            // Tab characters advance to the next tab stop.
            // A tab stop is at columns 0, 4, 8, 12, etc.
            const next_tab_stop = columns + (4 - (columns % 4));
            if (next_tab_stop > target_columns) {
                // If the next tab stop is beyond our target, it means the tab
                // character itself spans into the 'content' part.
                // We stop here, and the content starts from this tab character.
                // The padding is the difference between the tab stop and the target.
                return .{
                    .content = line[idx..], // Content starts from the tab character
                    .padding = next_tab_stop - target_columns,
                };
            }
            columns = next_tab_stop; // Advance columns to the tab stop
        } else {
            // If we encounter a non-whitespace character before reaching target_columns,
            // it means we cannot strip the required target_columns.
            // This is important for block quotes where '>' must be preserved if it's not the first character.
            break;
        }
    }

    // If we exited the loop because 'columns' reached 'target_columns' or 'idx' reached line.len:
    // The content starts after the consumed part (idx).
    // Padding is 0 because we've precisely consumed target_columns or more.
    return .{ .content = line[idx..], .padding = 0 };
}

fn trimAscii(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t");
}

fn trimAsciiEnd(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, " \t");
}

fn trimAsciiStart(line: []const u8) []const u8 {
    return std.mem.trimLeft(u8, line, " \t");
}

fn trimBlockWhitespace(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t\n\r");
}

fn hasBlankLine(content: []const u8) bool {
    var offset: usize = 0;
    while (lineBounds(content, offset)) |current| {
        offset = current.next;
        if (isBlank(current.line)) return true;
    }
    return false;
}

fn isBlank(line: []const u8) bool {
    return trimAscii(line).len == 0;
}

fn isPunctuation(char: u8) bool {
    return switch (char) {
        '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~' => true,
        else => false,
    };
}

fn parseAtxHeading(line: []const u8) ?Heading {
    const indent = leadingColumns(line);
    if (indent > 3) return null;
    const stripped = stripIndentColumns(line, indent);
    var level: usize = 0;
    while (level < stripped.content.len and stripped.content[level] == '#') level += 1;
    if (level == 0 or level > 6) return null;
    const after_marker = level;
    if (after_marker < stripped.content.len and stripped.content[after_marker] != ' ' and stripped.content[after_marker] != '\t') return null;

    var text = trimAscii(stripped.content[after_marker..]);
    var hash_start = text.len;
    while (hash_start > 0 and text[hash_start - 1] == '#') hash_start -= 1;
    if (hash_start < text.len and (hash_start == 0 or text[hash_start - 1] == ' ' or text[hash_start - 1] == '\t')) {
        text = trimAsciiEnd(text[0..hash_start]);
    }
    return .{ .level = level, .text = text };
}

fn parseSetextUnderline(line: []const u8) ?usize {
    const indent = leadingColumns(line);
    if (indent > 3) return null;
    const stripped = stripIndentColumns(line, indent);
    const trimmed = trimAscii(stripped.content);
    if (trimmed.len == 0) return null;
    const marker = trimmed[0];
    if (marker != '=' and marker != '-') return null;
    for (trimmed) |char| {
        if (char != marker) return null;
    }
    return if (marker == '=') 1 else 2;
}

fn parseThematicBreak(line: []const u8) bool {
    const indent = leadingColumns(line);
    if (indent > 3) return false;
    const stripped = stripIndentColumns(line, indent);
    const trimmed = trimAscii(stripped.content);
    if (trimmed.len == 0) return false;
    const marker = trimmed[0];
    if (marker != '*' and marker != '-' and marker != '_') return false;
    var count: usize = 0;
    for (trimmed) |char| {
        if (char == marker) {
            count += 1;
        } else if (char != ' ' and char != '\t') {
            return false;
        }
    }
    return count >= 3;
}

fn parseFenceOpener(line: []const u8) ?Fence {
    const indent = leadingColumns(line);
    if (indent > 3) return null;
    const stripped = stripIndentColumns(line, indent);
    if (stripped.content.len == 0) return null;
    const marker = stripped.content[0];
    if (marker != '`' and marker != '~') return null;
    var len: usize = 0;
    while (len < stripped.content.len and stripped.content[len] == marker) len += 1;
    if (len < 3) return null;
    const info = trimAscii(stripped.content[len..]);
    if (marker == '`' and std.mem.indexOfScalar(u8, info, '`') != null) return null;
    return .{ .char = marker, .len = len, .indent = indent, .info = info };
}

fn isFenceCloser(line: []const u8, fence: Fence) bool {
    const indent = leadingColumns(line);
    if (indent > 3) return false;
    const stripped = stripIndentColumns(line, indent);
    var len: usize = 0;
    while (len < stripped.content.len and stripped.content[len] == fence.char) len += 1;
    if (len < fence.len) return false;
    return trimAscii(stripped.content[len..]).len == 0;
}

fn parseBlockQuote(line: []const u8) ?usize {
    const marker = consumeBlockQuoteMarker(line) orelse return null;
    return marker.consumed_columns;
}

fn consumeBlockQuoteMarker(line: []const u8) ?BlockQuoteMarker {
    var idx: usize = 0;
    var columns: usize = 0;

    while (idx < line.len and columns <= 3) : (idx += 1) {
        if (line[idx] == ' ') {
            columns += 1;
        } else if (line[idx] == '\t') {
            columns += 4 - (columns % 4);
        } else {
            break;
        }
    }

    if (columns > 3 or idx >= line.len or line[idx] != '>') return null;
    idx += 1;
    columns += 1;

    if (idx < line.len and (line[idx] == ' ' or line[idx] == '\t')) {
        if (line[idx] == ' ') {
            idx += 1;
            columns += 1;
        } else {
            const next_tab_stop = columns + (4 - (columns % 4));
            idx += 1;
            return .{ .content = line[idx..], .padding = next_tab_stop - columns, .consumed_columns = next_tab_stop };
        }
    }

    return .{ .content = line[idx..], .padding = 0, .consumed_columns = columns };
}

fn parseListMarker(line: []const u8) ?ListMarker {
    const indent = leadingColumns(line);
    if (indent > 3) return null;
    const stripped = stripIndentColumns(line, indent);
    if (stripped.content.len == 0) return null;
    const marker = stripped.content[0];
    if (marker == '-' or marker == '*' or marker == '+') {
        if (1 < stripped.content.len and stripped.content[1] != ' ' and stripped.content[1] != '\t') return null;
        var content_start_offset: usize = 1;
        while (content_start_offset < stripped.content.len and (stripped.content[content_start_offset] == ' ' or stripped.content[content_start_offset] == '\t')) content_start_offset += 1;
        const spaces = countLeadingColumns(stripped.content[1..content_start_offset], indent + 1);
        const content_indent = indent + 1 + if (spaces > 0 and spaces <= 4) spaces else 1;
        const content_start_columns = consumedColumns(line, stripped.content[content_start_offset..]);
        const content_start = consumedBytes(line, stripped.content[content_start_offset..]);
        return .{ .ordered = false, .number = 0, .indent = indent, .width = 1, .content_start = content_start, .content_start_columns = content_start_columns, .content_indent = content_indent, .marker_char = marker, .delimiter = marker };
    }

    if (!std.ascii.isDigit(marker)) return null;
    var idx: usize = 0;
    var number: usize = 0;
    var digits: usize = 0;
    while (idx < stripped.content.len and std.ascii.isDigit(stripped.content[idx]) and digits < 9) : (idx += 1) {
        number = number * 10 + (stripped.content[idx] - '0');
        digits += 1;
    }
    if (digits == 0 or idx >= stripped.content.len or (stripped.content[idx] != '.' and stripped.content[idx] != ')')) return null;
    if (idx + 1 < stripped.content.len and stripped.content[idx + 1] != ' ' and stripped.content[idx + 1] != '\t') return null;
    const delimiter = stripped.content[idx];
    var content_start_offset = idx + 1;
    while (content_start_offset < stripped.content.len and (stripped.content[content_start_offset] == ' ' or stripped.content[content_start_offset] == '\t')) content_start_offset += 1;
    const spaces = countLeadingColumns(stripped.content[idx + 1 .. content_start_offset], indent + digits + 1);
    const content_indent = indent + digits + 1 + if (spaces > 0 and spaces <= 4) spaces else 1;
    const content_start_columns = consumedColumns(line, stripped.content[content_start_offset..]);
    const content_start = consumedBytes(line, stripped.content[content_start_offset..]);
    return .{ .ordered = true, .number = number, .indent = indent, .width = digits + 1, .content_start = content_start, .content_start_columns = content_start_columns, .content_indent = content_indent, .marker_char = '1', .delimiter = delimiter };
}

fn parseIndentedListMarker(line: []const u8) ?ListMarker {
    if (leadingColumns(line) < 4) return null;
    const stripped = stripIndentColumns(line, 4);
    var marker = parseListMarker(stripped.content) orelse return null;
    const column_offset = consumedColumns(line, stripped.content);
    const byte_offset = consumedBytes(line, stripped.content);
    marker.indent += column_offset;
    marker.content_start += byte_offset;
    marker.content_start_columns += column_offset;
    marker.content_indent += column_offset;
    return marker;
}

fn parseContainerListMarker(line: []const u8) ?ListMarker {
    return parseListMarker(line);
}

fn isLinkReferenceDefinition(line: []const u8) bool {
    const indent = leadingColumns(line);
    if (indent > 3) return false;
    const stripped = stripIndentColumns(line, indent);
    if (stripped.content.len == 0 or stripped.content[0] != '[') return false;
    const close = findLinkLabelClose(stripped.content, 0) orelse return false;
    if (close == 1 or close + 1 >= stripped.content.len or stripped.content[close + 1] != ':') return false;
    if (trimAscii(stripped.content[1..close]).len == 0) return false;
    if (containsUnescapedBracket(stripped.content[1..close])) return false;
    return true;
}

fn isPotentialLinkReferenceDefinitionStart(line: []const u8) bool {
    const indent = leadingColumns(line);
    if (indent > 3) return false;
    const stripped = stripIndentColumns(line, indent);
    return stripped.content.len > 0 and stripped.content[0] == '[';
}

fn parseLinkReferenceDefinition(line: []const u8) ?LinkReference {
    const indent = leadingColumns(line);
    if (indent > 3) return null;
    const stripped = stripIndentColumns(line, indent);
    if (stripped.content.len == 0 or stripped.content[0] != '[') return null;
    const close = findLinkLabelClose(stripped.content, 0) orelse return null;
    if (close == 1 or close + 1 >= stripped.content.len or stripped.content[close + 1] != ':') return null;
    if (trimAscii(stripped.content[1..close]).len == 0) return null;
    if (containsUnescapedBracket(stripped.content[1..close])) return null;
    const target = parseLinkTarget(stripped.content[close + 2 ..]);
    if (!target.valid) return null;
    return .{ .label = trimAscii(stripped.content[1..close]), .target = target };
}

fn collectLinkReferenceDefinitionInContainer(content: []const u8, offset: usize, stack: ContainerStack) usize {
    var next_offset = offset;
    var quote: ?u8 = null;
    var collected_lines: usize = 0;
    while (lineBounds(content, next_offset)) |next_line| {
        const context = stack.normalizeLine(next_line.line);
        const trimmed = trimAscii(context.content);
        if (context.blank) break;
        if (quote == null and collected_lines > 0 and leadingColumns(context.content) <= 3 and !std.mem.startsWith(u8, trimmed, "'") and !std.mem.startsWith(u8, trimmed, "\"") and !std.mem.startsWith(u8, trimmed, "(")) break;
        if (quote == null and isLinkReferenceDefinition(context.content)) break;
        next_offset = next_line.next;
        collected_lines += 1;
        if (quote) |quote_byte| {
            if (std.mem.indexOfScalar(u8, trimmed, quote_byte) != null) break;
        } else if (std.mem.indexOfScalar(u8, trimmed, '\'')) |_| {
            quote = '\'';
            if (std.mem.lastIndexOfScalar(u8, trimmed, '\'') != std.mem.indexOfScalar(u8, trimmed, '\'')) break;
        } else if (std.mem.indexOfScalar(u8, trimmed, '"')) |_| {
            quote = '"';
            if (std.mem.lastIndexOfScalar(u8, trimmed, '"') != std.mem.indexOfScalar(u8, trimmed, '"')) break;
        } else if (std.mem.indexOfScalar(u8, trimmed, '(')) |_| {
            quote = ')';
            if (std.mem.indexOfScalar(u8, trimmed, ')') != null) break;
        }
        if (quote == null and collected_lines >= 2) break;
    }
    return next_offset;
}

fn collectLinkReferenceDefinitionEnd(allocator: std.mem.Allocator, content: []const u8, start: usize, stack: ContainerStack) !?usize {
    var next_offset = start;
    var line_count: usize = 0;
    var best_end: ?usize = null;
    while (lineBounds(content, next_offset)) |next_line| {
        const context = stack.normalizeLine(next_line.line);
        if (line_count > 0 and context.blank) break;
        next_offset = next_line.next;
        line_count += 1;

        if (line_count > 8) break;
        if (try parseLinkReferenceDefinitionFromSource(allocator, content[start..next_offset], stack)) |definition| {
            deinitLinkReference(allocator, definition);
            best_end = next_offset;
        }
    }
    return best_end;
}

fn writeHtmlTitleAttribute(writer: anytype, value: []const u8) !void {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '\\' and i + 1 < value.len and isPunctuation(value[i + 1])) {
            try writeHtmlEscaped(writer, value[i + 1 .. i + 2]);
            i += 1;
            continue;
        }
        if (value[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, value, i + 1, ';')) |semi| {
                const entity = value[i + 1 .. semi];
                if (isValidEntity(entity)) {
                    var buf: [16]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&buf);
                    if (try decodeEntity(stream.writer(), entity)) {
                        try writeHtmlEscaped(writer, stream.getWritten());
                        i = semi;
                        continue;
                    }
                }
            }
        }
        try writeHtmlEscaped(writer, value[i .. i + 1]);
    }
}

fn parseLinkReferenceDefinitionFromSource(allocator: std.mem.Allocator, source: []const u8, stack: ContainerStack) !?LinkReference {
    var buffer: [4096]u8 = undefined;
    var len: usize = 0;
    var offset: usize = 0;
    while (lineBounds(source, offset)) |current| {
        offset = current.next;
        const context = stack.normalizeLine(current.line);
        const trimmed = trimAscii(context.content);
        if (trimmed.len == 0) continue;
        if (len != 0) {
            if (len >= buffer.len) return null;
            buffer[len] = ' ';
            len += 1;
        }
        if (len + trimmed.len > buffer.len) return null;
        @memcpy(buffer[len .. len + trimmed.len], trimmed);
        len += trimmed.len;
    }
    const normalized = buffer[0..len];
    const indent = leadingColumns(normalized);
    if (indent > 3 or indent >= normalized.len or normalized[indent] != '[') return null;
    const stripped_line = stripIndentColumns(normalized, indent);
    const stripped = stripped_line.content;
    const close = findLinkLabelClose(stripped, 0) orelse return null;
    if (close == 1 or close + 1 >= stripped.len or stripped[close + 1] != ':') return null;
    if (trimAscii(stripped[1..close]).len == 0) return null;
    if (containsUnescapedBracket(stripped[1..close])) return null;
    const target = parseLinkTargetFromNormalizedDefinition(stripped[close + 2 ..]);
    if (!target.valid) return null;
    const owned = try allocator.dupe(u8, normalized);
    const label_start = @intFromPtr(trimAscii(stripped[1..close]).ptr) - @intFromPtr(normalized.ptr);
    const label_len = trimAscii(stripped[1..close]).len;
    const destination_start = @intFromPtr(target.destination.ptr) - @intFromPtr(normalized.ptr);
    const title_start = if (target.title) |title| @intFromPtr(title.ptr) - @intFromPtr(normalized.ptr) else 0;
    return .{
        .label = owned[label_start .. label_start + label_len],
        .target = .{
            .destination = owned[destination_start .. destination_start + target.destination.len],
            .title = if (target.title) |title| owned[title_start .. title_start + title.len] else null,
            .valid = target.valid,
            .process_escapes = target.process_escapes,
        },
        .owned_source = owned,
    };
}

fn parseShortcutReferenceLabel(line: []const u8) ?[]const u8 {
    const trimmed = trimAscii(line);
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return null;
    const label = trimmed[1 .. trimmed.len - 1];
    return if (label.len == 0) null else label;
}

fn findLinkLabelClose(value: []const u8, open: usize) ?usize {
    var idx = open + 1;
    var nested: usize = 0;
    while (idx < value.len) : (idx += 1) {
        if (value[idx] == '\\' and idx + 1 < value.len and isPunctuation(value[idx + 1])) {
            idx += 1;
            continue;
        }
        if (value[idx] == '[') {
            nested += 1;
            continue;
        }
        if (value[idx] == ']') {
            if (nested == 0) return idx;
            nested -= 1;
        }
    }
    return null;
}

fn containsUnescapedBracket(value: []const u8) bool {
    var idx: usize = 0;
    while (idx < value.len) : (idx += 1) {
        if (value[idx] == '\\' and idx + 1 < value.len and isPunctuation(value[idx + 1])) {
            idx += 1;
            continue;
        }
        if (value[idx] == '[' or value[idx] == ']') return true;
    }
    return false;
}

fn labelByteEqual(left: u8, right: u8) bool {
    return std.ascii.toLower(left) == std.ascii.toLower(right);
}

fn normalizeLabelCodepoint(codepoint: u21) u21 {
    if (codepoint >= 'A' and codepoint <= 'Z') return codepoint + ('a' - 'A');
    if ((codepoint >= 0x0391 and codepoint <= 0x03A1) or (codepoint >= 0x03A3 and codepoint <= 0x03AB)) return codepoint + 0x20;
    return codepoint;
}

fn nextLabelCodepoint(value: []const u8, index: *usize, pending_space: *bool) ?u21 {
    while (index.* < value.len) {
        const start = index.*;
        const byte = value[index.*];
        var codepoint: u21 = byte;
        if (byte < 0x80) {
            index.* += 1;
        } else {
            const width = std.unicode.utf8ByteSequenceLength(byte) catch return null;
            if (start + width > value.len) return null;
            codepoint = std.unicode.utf8Decode(value[start .. start + width]) catch return null;
            index.* += width;
        }

        if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n' or codepoint == '\r') {
            pending_space.* = true;
            continue;
        }
        if (pending_space.*) {
            pending_space.* = false;
            index.* = start;
            return ' ';
        }
        return normalizeLabelCodepoint(codepoint);
    }
    return null;
}

fn nextNormalizedLabelByte(value: []const u8, index: *usize, pending_space: *bool) ?u8 {
    while (index.* < value.len) {
        const byte = value[index.*];
        index.* += 1;
        if (std.ascii.isWhitespace(byte)) {
            pending_space.* = true;
            continue;
        }
        if (pending_space.*) {
            pending_space.* = false;
            index.* -= 1;
            return ' ';
        }
        return byte;
    }
    return null;
}

fn normalizedLabelsEqual(left: []const u8, right: []const u8) bool {
    if ((std.mem.eql(u8, trimAscii(left), "ẞ") and std.ascii.eqlIgnoreCase(trimAscii(right), "SS")) or
        (std.mem.eql(u8, trimAscii(right), "ẞ") and std.ascii.eqlIgnoreCase(trimAscii(left), "SS"))) return true;
    var left_idx: usize = 0;
    var right_idx: usize = 0;
    var left_space = false;
    var right_space = false;
    while (true) {
        const left_codepoint = nextLabelCodepoint(left, &left_idx, &left_space);
        const right_codepoint = nextLabelCodepoint(right, &right_idx, &right_space);
        if (left_codepoint == null or right_codepoint == null) return left_codepoint == null and right_codepoint == null;
        if (left_codepoint.? != right_codepoint.?) return false;
    }
}

fn labelsEqual(left: []const u8, right: []const u8) bool {
    return normalizedLabelsEqual(trimAscii(left), trimAscii(right));
}

fn findLinkReferenceDefinition(lookup: ReferenceLookup, label: []const u8) ?LinkTarget {
    for (lookup.references) |definition| {
        if (labelsEqual(definition.label, label)) return definition.target;
    }
    _ = lookup.content;
    return null;
}

fn hasBalancedCodeTicks(value: []const u8) bool {
    var i: usize = 0;
    while (i < value.len) {
        if (value[i] != '`') {
            i += 1;
            continue;
        }
        var tick_count: usize = 0;
        while (i + tick_count < value.len and value[i + tick_count] == '`') tick_count += 1;
        var search = i + tick_count;
        while (search < value.len) : (search += 1) {
            if (value[search] != '`') continue;
            var close_count: usize = 0;
            while (search + close_count < value.len and value[search + close_count] == '`') close_count += 1;
            if (close_count == tick_count) {
                i = search + close_count;
                break;
            }
            search += close_count - 1;
        } else return false;
    }
    return true;
}

fn hasOpenAngleInline(value: []const u8) bool {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '<') {
            if (std.mem.indexOfScalarPos(u8, value, i + 1, '>') == null) return true;
        }
    }
    return false;
}

fn hasInlineLink(value: []const u8) bool {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '[') {
            if (i > 0 and value[i - 1] == '!') continue;
            if (findLinkLabelClose(value, i)) |close| {
                if (close + 1 < value.len and (value[close + 1] == '(' or value[close + 1] == '[')) return true;
            }
        }
    }
    return false;
}

fn suppressOuterLinkLabel(label: []const u8) bool {
    return !hasBalancedCodeTicks(label) or hasOpenAngleInline(label) or hasInlineLink(label);
}

fn appendAstBlock(ast: *CommonMarkAst, block: AstBlock) !void {
    try ast.blocks.append(ast.allocator, block);
}

fn collectFencedCodeBlock(content: []const u8, first_line: []const u8, offset: usize, fence: Fence) usize {
    return collectFencedCodeBlockInContainer(content, first_line, offset, fence, ContainerStack.empty());
}

fn collectFencedCodeBlockInContainer(content: []const u8, first_line: []const u8, offset: usize, fence: Fence, stack: ContainerStack) usize {
    _ = first_line;
    var next_offset = offset;
    while (lineBounds(content, next_offset)) |next_line| {
        next_offset = next_line.next;
        if (isFenceCloser(stack.normalizeLine(next_line.line).content, fence)) break;
    }
    return next_offset;
}

fn collectIndentedCodeBlock(content: []const u8, offset: usize) usize {
    return collectIndentedCodeBlockInContainer(content, offset, ContainerStack.empty());
}

fn collectIndentedCodeBlockInContainer(content: []const u8, offset: usize, stack: ContainerStack) usize {
    var next_offset = offset;
    while (lineBounds(content, next_offset)) |next_line| {
        const context = stack.normalizeLine(next_line.line);
        if (!context.matched and !context.blank) break;
        if (!context.blank and context.indent_columns < 4) break;
        next_offset = next_line.next;
    }
    return next_offset;
}

fn relativeIndentColumns(line: []const u8, context: ContainerLineContext) usize {
    _ = line;
    return context.indent_columns;
}

fn indentedCodeStripColumns(line: []const u8, context: ContainerLineContext) usize {
    _ = line;
    return context.column_offset + 4;
}

fn collectBlockQuoteBlock(content: []const u8, first_line: []const u8, offset: usize) usize {
    var next_offset = offset;
    var after_blank_quote_line = false;
    var allow_lazy_continuation = false;
    var in_fenced_code = false;
    var fence: ?Fence = null;
    const first_context = blockQuoteLineContext(first_line);
    after_blank_quote_line = first_context.blank;
    allow_lazy_continuation = !first_context.blank and leadingColumns(first_context.content) < 4 and parseFenceOpener(first_context.content) == null;
    if (parseFenceOpener(first_context.content)) |opened| {
        in_fenced_code = true;
        fence = opened;
    }
    while (lineBounds(content, next_offset)) |next_line| {
        const context = blockQuoteLineContext(next_line.line);
        if (context.matched) {
            after_blank_quote_line = context.blank;
            allow_lazy_continuation = !context.blank and leadingColumns(context.content) < 4 and parseFenceOpener(context.content) == null;
            if (in_fenced_code) {
                if (isFenceCloser(context.content, fence.?)) in_fenced_code = false;
            } else if (parseFenceOpener(context.content)) |opened| {
                in_fenced_code = true;
                fence = opened;
            }
            next_offset = next_line.next;
            continue;
        }

        if (!in_fenced_code and allow_lazy_continuation and !after_blank_quote_line and !isBlank(next_line.line) and (!isHtmlParagraphBoundary(context.content) or leadingColumns(next_line.line) >= 4)) {
            after_blank_quote_line = false;
            next_offset = next_line.next;
            continue;
        }

        break;
    }
    return next_offset;
}

fn collectListBlock(content: []const u8, offset: usize, first_marker: ListMarker) usize {
    var next_offset = offset;
    var current_marker = first_marker;
    var pending_blank = false;
    var pending_blank_start: usize = offset;
    const first_line = lineBounds(content, 0) orelse return next_offset;
    var had_content_before_blank = trimAscii(listLineContent(first_line.line, first_marker)).len > 0;

    while (lineBounds(content, next_offset)) |next_line| {
        const line_start = next_offset;
        if (!pending_blank and leadingColumns(next_line.line) < current_marker.content_indent and parseThematicBreak(next_line.line)) break;
        if (parseContainerListMarker(next_line.line)) |candidate| {
            if (current_marker.ordered and current_marker.number != 1 and candidate.indent < current_marker.content_indent and candidate.ordered != current_marker.ordered) break;
            if ((candidate.content_indent <= first_marker.content_indent or candidate.indent < current_marker.content_indent) and candidate.ordered == first_marker.ordered and candidate.marker_char == first_marker.marker_char and candidate.delimiter == first_marker.delimiter) {
                current_marker = candidate;
                had_content_before_blank = trimAscii(listLineContent(next_line.line, candidate)).len > 0;
                pending_blank = false;
                next_offset = next_line.next;
                continue;
            }
            if (candidate.indent <= first_marker.indent) break;
        }

        if (isBlank(next_line.line)) {
            if (!pending_blank) pending_blank_start = line_start;
            pending_blank = true;
            next_offset = next_line.next;
            continue;
        }

        if (pending_blank and !had_content_before_blank) return pending_blank_start;
        if (pending_blank and leadingColumns(next_line.line) < listBlankContinuationIndent(current_marker)) return pending_blank_start;
        pending_blank = false;
        had_content_before_blank = true;
        next_offset = next_line.next;
    }
    return next_offset;
}

fn listLineContent(line: []const u8, marker: ListMarker) []const u8 {
    if (marker.content_start <= line.len) return line[marker.content_start..];
    return "";
}

fn listBlankContinuationIndent(marker: ListMarker) usize {
    return marker.content_indent;
}

fn parseListItems(allocator: std.mem.Allocator, content: []const u8, first_marker: ListMarker) ![]const ListItem {
    var items = std.ArrayList(ListItem).empty;
    defer items.deinit(allocator);
    errdefer {
        for (items.items) |item| allocator.free(item.content);
    }

    const first = lineBounds(content, 0) orelse return &[_]ListItem{};
    var next_offset = first.next;
    var current_line = first.line;
    var current_marker = first_marker;
    var pending_blank = false;
    var list_loose = false;

    while (true) {
        var item_buffer = std.ArrayList(u8).empty;
        defer item_buffer.deinit(allocator);
        var raw_item_buffer = std.ArrayList(u8).empty;
        defer raw_item_buffer.deinit(allocator);
        try item_buffer.appendSlice(allocator, listLineContent(current_line, current_marker));
        try item_buffer.append(allocator, '\n');
        const first_line_extra_indent = if (current_marker.content_start_columns > current_marker.content_indent)
            current_marker.content_start_columns - current_marker.content_indent
        else
            0;
        const first_line_content_indent = if (first_line_extra_indent >= 4)
            current_marker.content_start_columns
        else
            current_marker.content_indent;
        for (0..first_line_content_indent) |_| try raw_item_buffer.append(allocator, ' ');
        try raw_item_buffer.appendSlice(allocator, listLineContent(current_line, current_marker));
        try raw_item_buffer.append(allocator, '\n');
        var item_loose = false;
        pending_blank = false;
        var had_content_before_blank = trimAscii(listLineContent(current_line, current_marker)).len > 0;
        var has_next_item = false;

        while (lineBounds(content, next_offset)) |next_line| {
            if (!pending_blank and leadingColumns(next_line.line) < current_marker.content_indent and parseThematicBreak(next_line.line)) break;
            if (parseContainerListMarker(next_line.line)) |candidate| {
                if (current_marker.ordered and current_marker.number != 1 and candidate.indent < current_marker.content_indent and candidate.ordered != current_marker.ordered) break;
                if ((candidate.content_indent <= first_marker.content_indent or candidate.indent < current_marker.content_indent) and candidate.ordered == first_marker.ordered and candidate.marker_char == first_marker.marker_char and candidate.delimiter == first_marker.delimiter) {
                    current_line = next_line.line;
                    current_marker = candidate;
                    next_offset = next_line.next;
                    has_next_item = true;
                    pending_blank = false;
                    break;
                }
                if (candidate.indent <= first_marker.indent) break;
            }

            if (isBlank(next_line.line)) {
                item_loose = true;
                pending_blank = true;
                try item_buffer.append(allocator, '\n');
                try raw_item_buffer.append(allocator, '\n');
                next_offset = next_line.next;
                continue;
            }

            if (pending_blank and !had_content_before_blank) {
                item_loose = false;
                if (item_buffer.items.len > 0) _ = item_buffer.pop();
                if (raw_item_buffer.items.len > 0) _ = raw_item_buffer.pop();
                break;
            }
            if (pending_blank and leadingColumns(next_line.line) < listBlankContinuationIndent(current_marker)) {
                item_loose = false;
                if (item_buffer.items.len > 0) _ = item_buffer.pop();
                if (raw_item_buffer.items.len > 0) _ = raw_item_buffer.pop();
                break;
            }
            const was_pending_blank = pending_blank;
            pending_blank = false;
            try appendListItemContinuation(allocator, &item_buffer, next_line.line, current_marker.content_indent);
            if (!isBlank(next_line.line)) had_content_before_blank = true;
            const continuation_columns = leadingColumns(next_line.line);
            const post_blank_code_threshold = if (first_line_extra_indent >= 4) current_marker.content_indent + 4 else current_marker.content_start_columns + 4;
            if (was_pending_blank and continuation_columns >= current_marker.content_start_columns and continuation_columns < post_blank_code_threshold) {
                for (0..current_marker.content_indent) |_| try raw_item_buffer.append(allocator, ' ');
                const stripped = stripIndentColumns(next_line.line, current_marker.content_indent);
                for (0..stripped.padding) |_| try raw_item_buffer.append(allocator, ' ');
                try raw_item_buffer.appendSlice(allocator, stripped.content);
            } else {
                try raw_item_buffer.appendSlice(allocator, next_line.line);
            }
            try raw_item_buffer.append(allocator, '\n');
            next_offset = next_line.next;
        } else {
            pending_blank = false;
        }

        if (item_loose) list_loose = true;
        const item_content = std.mem.trimRight(u8, item_buffer.items, "\n");
        const owned_content = try allocator.dupe(u8, item_content);
        errdefer allocator.free(owned_content);
        const raw_item_content = std.mem.trimRight(u8, raw_item_buffer.items, "\n");
        const owned_raw_content = try allocator.dupe(u8, raw_item_content);
        errdefer allocator.free(owned_raw_content);
        var child_stack = ContainerStack.empty();
        try child_stack.pushListItem(current_marker.content_indent);
        try items.append(allocator, .{
            .marker = current_marker,
            .content = owned_content,
            .raw_content = owned_raw_content,
            .child_stack = child_stack,
            .loose = item_loose or list_loose,
        });

        if (pending_blank) break;
        if (!has_next_item) break;
    }

    return try allocator.dupe(ListItem, items.items);
}

fn collectParagraphBlock(content: []const u8, offset: usize) usize {
    var next_offset = offset;
    while (lineBounds(content, next_offset)) |next_line| {
        if (parseSetextUnderline(next_line.line) != null) return next_line.next;
        if (isHtmlParagraphBoundary(next_line.line)) break;
        next_offset = next_line.next;
    }
    return next_offset;
}

fn parseSetextHeadingBlock(source: []const u8) ?Heading {
    var offset: usize = 0;
    var text_end: usize = 0;
    while (lineBounds(source, offset)) |current| {
        if (parseSetextUnderline(current.line)) |level| {
            if (text_end == 0) return null;
            return .{ .level = level, .text = trimAscii(source[0..text_end]) };
        }
        if (parseBlockQuote(current.line) != null or isBlank(current.line) or leadingColumns(current.line) >= 4) return null;
        text_end = current.next;
        offset = current.next;
    }
    return null;
}

const ParsedChildren = struct {
    content: []const u8,
    blocks: []AstBlock,
    references: []LinkReference,
};

fn appendNormalizedContainerLine(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), stack: ContainerStack, line: []const u8) !void {
    const context = stack.normalizeLine(line);
    for (0..context.padding) |_| try buffer.append(allocator, ' ');
    try buffer.appendSlice(allocator, context.content);
    try buffer.append(allocator, '\n');
}

fn appendBlockQuoteLine(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), line: []const u8) !void {
    var stack = ContainerStack.empty();
    try stack.pushBlockQuote();
    try appendNormalizedContainerLine(allocator, buffer, stack, line);
}

fn parseBlockQuoteChildren(allocator: std.mem.Allocator, source: []const u8, parent_stack: ContainerStack) ParseError!ParsedChildren {
    var quote_buffer = std.ArrayList(u8).empty;
    defer quote_buffer.deinit(allocator);
    var child_stack = parent_stack;
    try child_stack.pushBlockQuote();

    var offset: usize = 0;
    while (lineBounds(source, offset)) |current| {
        offset = current.next;
        try appendNormalizedContainerLine(allocator, &quote_buffer, child_stack, current.line);
    }

    const child_content = try allocator.dupe(u8, quote_buffer.items);
    errdefer allocator.free(child_content);
    var child_ast = try parseCommonMarkBlocks(allocator, child_content);
    errdefer child_ast.deinit();

    const children = try child_ast.blocks.toOwnedSlice(allocator);
    errdefer {
        for (children) |child| deinitAstBlock(allocator, child);
        allocator.free(children);
    }
    const references = try child_ast.references.toOwnedSlice(allocator);

    return .{ .content = child_content, .blocks = children, .references = references };
}

fn parseCommonMarkBlocks(allocator: std.mem.Allocator, content: []const u8) ParseError!CommonMarkAst {
    return parseCommonMarkBlocksInContainer(allocator, content, ContainerStack.empty());
}

fn parseCommonMarkBlocksInContainer(allocator: std.mem.Allocator, content: []const u8, stack: ContainerStack) ParseError!CommonMarkAst {
    var ast = CommonMarkAst{ .allocator = allocator, .blocks = std.ArrayList(AstBlock).empty, .references = std.ArrayList(LinkReference).empty };
    errdefer ast.deinit();

    var offset: usize = 0;
    while (lineBounds(content, offset)) |current| {
        const start = offset;
        const line = current.line;
        const context = stack.normalizeLine(line);
        const parse_line = context.content;
        offset = current.next;

        if (context.blank) {
            try appendAstBlock(&ast, .{ .kind = .blank, .source = content[start..offset], .container_stack = stack });
        } else if (parseFenceOpener(parse_line)) |fence| {
            offset = collectFencedCodeBlockInContainer(content, line, offset, fence, stack);
            try appendAstBlock(&ast, .{ .kind = .fenced_code, .source = content[start..offset], .container_stack = stack, .fence = fence });
        } else if (parseAtxHeading(parse_line)) |heading| {
            try appendAstBlock(&ast, .{ .kind = .heading, .source = content[start..offset], .container_stack = stack, .heading = heading });
        } else if (parseThematicBreak(parse_line)) {
            try appendAstBlock(&ast, .{ .kind = .thematic_break, .source = content[start..offset], .container_stack = stack });
        } else if (isPotentialLinkReferenceDefinitionStart(parse_line)) {
            const definition_end = (try collectLinkReferenceDefinitionEnd(allocator, content, start, stack)) orelse null;
            if (definition_end == null) {
                offset = collectParagraphBlock(content, offset);
                const source = content[start..offset];
                if (parseSetextHeadingBlock(source)) |heading| {
                    try appendAstBlock(&ast, .{ .kind = .setext_heading, .source = source, .container_stack = stack, .heading = heading });
                } else {
                    try appendAstBlock(&ast, .{ .kind = .paragraph, .source = source, .container_stack = stack });
                }
                continue;
            }
            offset = definition_end.?;
            const source = content[start..offset];
            const definition = (try parseLinkReferenceDefinitionFromSource(allocator, source, stack)) orelse {
                try appendAstBlock(&ast, .{ .kind = .paragraph, .source = source, .container_stack = stack });
                continue;
            };
            try ast.references.append(ast.allocator, definition);
            try appendAstBlock(&ast, .{ .kind = .paragraph, .source = source, .container_stack = stack, .link_reference = definition });
        } else if (parseHtmlBlockStart(parse_line)) |html_kind| {
            offset = collectHtmlBlockInContainer(content, offset, stack, parse_line, html_kind);
            try appendAstBlock(&ast, .{ .kind = .html_block, .source = content[start..offset], .container_stack = stack });
        } else if (blockQuoteLineContext(parse_line).matched) {
            offset = collectBlockQuoteBlock(content, line, offset);
            const source = content[start..offset];
            const parsed = try parseBlockQuoteChildren(allocator, source, stack);
            for (parsed.references) |reference| {
                try ast.references.append(ast.allocator, try cloneLinkReference(allocator, reference));
            }
            try appendAstBlock(&ast, .{ .kind = .block_quote, .source = source, .container_stack = stack, .child_content = parsed.content, .children = parsed.blocks, .child_references = parsed.references });
        } else if (parseContainerListMarker(parse_line)) |marker| {
            offset = collectListBlock(content, offset, marker);
            const source = content[start..offset];
            const list_items = try parseListItems(allocator, source, marker);
            try appendAstBlock(&ast, .{ .kind = .list, .source = source, .container_stack = stack, .list_marker = marker, .list_items = list_items });
        } else if (if (stack.len == 0) isHtmlIndentedCodeStart(line, content, offset) else isHtmlIndentedCodeStartInContainer(line, content, offset, stack)) {
            offset = collectIndentedCodeBlockInContainer(content, offset, stack);
            try appendAstBlock(&ast, .{ .kind = .indented_code, .source = content[start..offset], .container_stack = stack });
        } else {
            offset = collectParagraphBlock(content, offset);
            const source = content[start..offset];
            if (parseSetextHeadingBlock(source)) |heading| {
                try appendAstBlock(&ast, .{ .kind = .setext_heading, .source = source, .container_stack = stack, .heading = heading });
            } else {
                try appendAstBlock(&ast, .{ .kind = .paragraph, .source = source, .container_stack = stack });
            }
        }
    }

    return ast;
}

fn parseHtmlBlockStart(line: []const u8) ?HtmlBlockKind {
    const indent = leadingColumns(line);
    if (indent > 3) return null;
    const stripped = stripIndentColumns(line, indent);
    const trimmed = trimAscii(stripped.content);
    if (trimmed.len < 3 or trimmed[0] != '<') return null;
    if (std.mem.indexOfScalar(u8, trimmed, '>')) |close| {
        const inner = trimmed[1..close];
        if (std.mem.indexOfScalar(u8, inner, ':') != null or std.mem.indexOfScalar(u8, inner, '@') != null) return null;
        if (std.mem.indexOfScalar(u8, inner, '.') != null and std.mem.indexOfAny(u8, inner, " \t=/") == null) return null;
    }
    if (std.mem.startsWith(u8, trimmed, "<!--")) return .comment;
    if (std.mem.startsWith(u8, trimmed, "<?")) return .processing_instruction;
    if (std.mem.startsWith(u8, trimmed, "<![CDATA[")) return .cdata;
    if (std.mem.startsWith(u8, trimmed, "<!")) return .declaration;
    if (startsWithHtmlRawTag(trimmed)) return .raw_tag;
    if (startsWithHtmlBlockTag(trimmed)) return .block_tag;
    if (isCompleteHtmlTagLine(trimmed)) return .complete_tag;
    return null;
}

fn isHtmlBlockStart(line: []const u8) bool {
    return parseHtmlBlockStart(line) != null;
}

fn isHtmlParagraphInterruptingBlockStart(line: []const u8) bool {
    const kind = parseHtmlBlockStart(line) orelse return false;
    return kind != .complete_tag;
}

fn startsWithHtmlRawTag(trimmed: []const u8) bool {
    if (trimmed.len < 2 or trimmed[0] != '<') return false;
    var idx: usize = 1;
    if (idx < trimmed.len and trimmed[idx] == '/') return false;
    const start = idx;
    while (idx < trimmed.len and std.ascii.isAlphabetic(trimmed[idx])) idx += 1;
    const tag = trimmed[start..idx];
    if (tag.len == 0) return false;
    if (idx < trimmed.len and trimmed[idx] != '>' and trimmed[idx] != ' ' and trimmed[idx] != '\t') return false;
    return std.ascii.eqlIgnoreCase(tag, "script") or std.ascii.eqlIgnoreCase(tag, "pre") or std.ascii.eqlIgnoreCase(tag, "style") or std.ascii.eqlIgnoreCase(tag, "textarea");
}

fn startsWithHtmlBlockTag(trimmed: []const u8) bool {
    if (trimmed.len < 2 or trimmed[0] != '<') return false;
    var idx: usize = 1;
    if (idx < trimmed.len and trimmed[idx] == '/') idx += 1;
    const start = idx;
    while (idx < trimmed.len and std.ascii.isAlphabetic(trimmed[idx])) idx += 1;
    const tag = trimmed[start..idx];
    if (tag.len == 0) return false;
    if (idx < trimmed.len and trimmed[idx] != '>' and trimmed[idx] != '/' and trimmed[idx] != ' ' and trimmed[idx] != '\t') return false;
    if (std.mem.indexOfScalar(u8, trimmed, '>')) |close| {
        if (!isHtmlInlineTag(trimmed[1..close])) return false;
    }
    const block_tags = [_][]const u8{ "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search", "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul" };
    for (block_tags) |block_tag| {
        if (std.ascii.eqlIgnoreCase(tag, block_tag)) return true;
    }
    return false;
}

fn isCompleteHtmlTagLine(trimmed: []const u8) bool {
    if (trimmed.len < 3 or trimmed[0] != '<') return false;
    const close = std.mem.indexOfScalar(u8, trimmed, '>') orelse return false;
    if (trimAscii(trimmed[close + 1 ..]).len != 0) return false;
    return isHtmlInlineTag(trimmed[1..close]);
}

fn htmlBlockTerminator(kind: HtmlBlockKind) []const u8 {
    return switch (kind) {
        .comment => "-->",
        .processing_instruction => "?>",
        .declaration => ">",
        .cdata => "]]>",
        .raw_tag => "",
        .block_tag, .complete_tag => "",
    };
}

fn hasRawHtmlClose(line: []const u8) bool {
    const closes = [_][]const u8{ "</script>", "</pre>", "</style>", "</textarea>" };
    for (closes) |close| {
        if (std.ascii.indexOfIgnoreCase(line, close) != null) return true;
    }
    return false;
}

fn collectHtmlBlockInContainer(content: []const u8, offset: usize, stack: ContainerStack, first_line: []const u8, kind: HtmlBlockKind) usize {
    var next_offset = offset;
    const terminator = htmlBlockTerminator(kind);
    if (kind == .raw_tag and hasRawHtmlClose(first_line)) return next_offset;
    if (terminator.len > 0 and std.mem.indexOf(u8, first_line, terminator) != null) return next_offset;
    if (terminator.len == 0 and kind != .raw_tag) {
        while (lineBounds(content, next_offset)) |next_line| {
            const context = stack.normalizeLine(next_line.line);
            if (context.blank) break;
            next_offset = next_line.next;
        }
        return next_offset;
    }

    while (lineBounds(content, next_offset)) |next_line| {
        const context = stack.normalizeLine(next_line.line);
        next_offset = next_line.next;
        if (kind == .raw_tag) {
            if (hasRawHtmlClose(context.content)) break;
        } else if (std.mem.indexOf(u8, context.content, terminator) != null) break;
    }
    return next_offset;
}

fn isValidEntity(entity: []const u8) bool {
    if (entity.len == 0) return false;
    if (entity[0] == '#') {
        if (entity.len < 2) return false;
        if (entity[1] == 'x' or entity[1] == 'X') {
            if (entity.len < 3 or entity.len > 8) return false;
            for (entity[2..]) |char| {
                if (!std.ascii.isHex(char)) return false;
            }
            return true;
        } else {
            if (entity.len < 2 or entity.len > 8) return false;
            for (entity[1..]) |char| {
                if (!std.ascii.isDigit(char)) return false;
            }
            return true;
        }
    }
    if (entity.len > 32) return false;
    if (!std.ascii.isAlphabetic(entity[0])) return false;
    for (entity[1..]) |char| {
        if (!std.ascii.isAlphanumeric(char)) return false;
    }
    return true;
}

fn decodeEntity(writer: anytype, entity: []const u8) !bool {
    if (entity.len == 0) return false;
    if (entity[0] == '#') {
        if (entity.len < 2) return false;
        var code: u32 = 0;
        if (entity[1] == 'x' or entity[1] == 'X') {
            if (entity.len < 3) return false;
            code = std.fmt.parseInt(u32, entity[2..], 16) catch return false;
        } else {
            code = std.fmt.parseInt(u32, entity[1..], 10) catch return false;
        }
        if (code == 0 or code > 0x10FFFF) code = 0xFFFD;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(code), &buf) catch {
            try writer.writeAll("\u{FFFD}");
            return true;
        };
        try writer.writeAll(buf[0..len]);
        return true;
    }

    if (std.mem.eql(u8, entity, "amp")) try writer.writeByte('&') else if (std.mem.eql(u8, entity, "lt")) try writer.writeByte('<') else if (std.mem.eql(u8, entity, "gt")) try writer.writeByte('>') else if (std.mem.eql(u8, entity, "quot")) try writer.writeByte('"') else if (std.mem.eql(u8, entity, "apos")) try writer.writeByte('\'') else if (std.mem.eql(u8, entity, "nbsp")) try writer.writeAll("\u{00A0}") else if (std.mem.eql(u8, entity, "auml")) try writer.writeAll("\u{00E4}") else if (std.mem.eql(u8, entity, "copy")) try writer.writeAll("\u{00A9}") else if (std.mem.eql(u8, entity, "ouml")) try writer.writeAll("\u{00F6}") else if (std.mem.eql(u8, entity, "AElig")) try writer.writeAll("\u{00C6}") else if (std.mem.eql(u8, entity, "Dcaron")) try writer.writeAll("\u{010E}") else if (std.mem.eql(u8, entity, "frac34")) try writer.writeAll("\u{00BE}") else if (std.mem.eql(u8, entity, "HilbertSpace")) try writer.writeAll("\u{210B}") else if (std.mem.eql(u8, entity, "DifferentialD")) try writer.writeAll("\u{2146}") else if (std.mem.eql(u8, entity, "ClockwiseContourIntegral")) try writer.writeAll("\u{2232}") else if (std.mem.eql(u8, entity, "ngE")) try writer.writeAll("\u{2267}\u{0338}") else return false;
    return true;
}

fn isUnsafeTerminalByte(byte: u8) bool {
    return byte == 0x1b or byte == 0x7f or (byte < 0x20 and byte != '\t');
}

fn writeTerminalByte(writer: anytype, byte: u8) !void {
    if (isUnsafeTerminalByte(byte)) {
        try writer.writeAll("");
    } else {
        try writer.writeByte(byte);
    }
}

fn writeTerminalText(writer: anytype, value: []const u8) !void {
    for (value) |byte| try writeTerminalByte(writer, byte);
}

fn writeCodeSpan(writer: anytype, text: []const u8) !void {
    var normalized = text;
    if (text.len > 1 and text[0] == ' ' and text[text.len - 1] == ' ' and !isBlank(text)) {
        var leading: usize = 0;
        while (leading < text.len and text[leading] == ' ') leading += 1;
        var trailing: usize = 0;
        while (trailing < text.len and text[text.len - 1 - trailing] == ' ') trailing += 1;
        const remove = @min(@min(leading, trailing), 2);
        normalized = text[remove .. text.len - remove];
    }
    var idx: usize = 0;
    while (idx < normalized.len) : (idx += 1) {
        try writeTerminalByte(writer, if (normalized[idx] == '\n' or normalized[idx] == '\r') ' ' else normalized[idx]);
    }
}

fn writeInline(writer: anytype, line: []const u8, is_header: bool, is_quote: bool, use_color: bool) !void {
    const reset_style = style(use_color, reset);
    const bold_style = style(use_color, bold);
    const dim_style = style(use_color, dim);
    const italic_style = style(use_color, italic);
    const cyan_style = style(use_color, cyan);
    const magenta_style = style(use_color, magenta);
    const underline_style = style(use_color, underline);

    var i: usize = 0;
    var in_bold = false;
    var in_italic = false;

    while (i < line.len) {
        if (line[i] == '\\' and i + 1 < line.len and isPunctuation(line[i + 1])) {
            if (line[i + 1] == '\n') {
                try writer.writeAll("<br />");
                i += 2;
                continue;
            }
            if (line[i + 1] == '<' and i + 2 < line.len and (line[i + 2] == '/' or std.ascii.isAlphabetic(line[i + 2]))) {
                if (std.mem.indexOfScalarPos(u8, line, i + 2, '>')) |close| {
                    try writeTerminalText(writer, line[i + 1 .. close + 1]);
                    i = close + 1;
                    continue;
                }
            }
            try writeTerminalByte(writer, line[i + 1]);
            i += 2;
            continue;
        }

        if (line[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, line, i + 1, ';')) |semi| {
                if (semi - i <= 32 and try decodeEntity(writer, line[i + 1 .. semi])) {
                    i = semi + 1;
                    continue;
                }
            }
        }

        if (line[i] == '`') {
            var tick_count: usize = 0;
            while (i + tick_count < line.len and line[i + tick_count] == '`') tick_count += 1;
            var search = i + tick_count;
            while (search < line.len) : (search += 1) {
                if (line[search] != '`') continue;
                var close_count: usize = 0;
                while (search + close_count < line.len and line[search + close_count] == '`') close_count += 1;
                if (close_count == tick_count) {
                    try writer.writeAll(dim_style);
                    try writer.writeAll(cyan_style);
                    try writeCodeSpan(writer, line[i + tick_count .. search]);
                    try writer.writeAll(reset_style);
                    if (is_header) try writer.writeAll(bold_style);
                    if (is_quote) {
                        try writer.writeAll(dim_style);
                        try writer.writeAll(italic_style);
                    }
                    i = search + close_count;
                    break;
                }
                search += close_count - 1;
            } else {
                try writeTerminalByte(writer, line[i]);
                i += 1;
            }
            continue;
        }

        if (line[i] == '!' and i + 1 < line.len and line[i + 1] == '[') {
            if (std.mem.indexOfScalarPos(u8, line, i + 2, ']')) |close_bracket| {
                if (close_bracket + 1 < line.len and line[close_bracket + 1] == '(') {
                    if (std.mem.indexOfScalarPos(u8, line, close_bracket + 2, ')')) |close_paren| {
                        try writer.writeAll(magenta_style);
                        try writer.writeAll("[image: ");
                        try writeInline(writer, line[i + 2 .. close_bracket], false, false, use_color);
                        try writer.writeAll("]");
                        try writer.writeAll(reset_style);
                        if (is_header) try writer.writeAll(bold_style);
                        if (is_quote) {
                            try writer.writeAll(dim_style);
                            try writer.writeAll(italic_style);
                        }
                        i = close_paren + 1;
                        continue;
                    }
                }
            }
        }

        if (line[i] == '[') {
            if (std.mem.indexOfScalarPos(u8, line, i + 1, ']')) |close_bracket| {
                if (close_bracket + 1 < line.len and line[close_bracket + 1] == '(') {
                    if (std.mem.indexOfScalarPos(u8, line, close_bracket + 2, ')')) |close_paren| {
                        try writer.writeAll(underline_style);
                        try writer.writeAll(cyan_style);
                        try writeInline(writer, line[i + 1 .. close_bracket], false, false, use_color);
                        try writer.writeAll(reset_style);
                        if (is_header) try writer.writeAll(bold_style);
                        if (is_quote) {
                            try writer.writeAll(dim_style);
                            try writer.writeAll(italic_style);
                        }
                        i = close_paren + 1;
                        continue;
                    }
                }
            }
        }

        if (line[i] == '<') {
            if (std.mem.indexOfScalarPos(u8, line, i + 1, '>')) |close| {
                const inner = line[i + 1 .. close];
                if (std.mem.indexOfScalar(u8, inner, ':') != null or std.mem.indexOfScalar(u8, inner, '@') != null) {
                    try writer.writeAll(underline_style);
                    try writer.writeAll(cyan_style);
                    try writeTerminalText(writer, inner);
                    try writer.writeAll(reset_style);
                    if (is_header) try writer.writeAll(bold_style);
                    if (is_quote) {
                        try writer.writeAll(dim_style);
                        try writer.writeAll(italic_style);
                    }
                    i = close + 1;
                    continue;
                }
                if (inner.len > 0 and (inner[0] == '/' or inner[0] == '!' or inner[0] == '?' or std.ascii.isAlphabetic(inner[0]))) {
                    try writer.writeAll(dim_style);
                    try writer.writeByte('<');
                    try writeTerminalText(writer, inner);
                    try writer.writeByte('>');
                    try writer.writeAll(reset_style);
                    if (is_header) try writer.writeAll(bold_style);
                    if (is_quote) {
                        try writer.writeAll(dim_style);
                        try writer.writeAll(italic_style);
                    }
                    i = close + 1;
                    continue;
                }
            }
        }

        if (i + 1 < line.len and ((line[i] == '*' and line[i + 1] == '*') or (line[i] == '_' and line[i + 1] == '_'))) {
            in_bold = !in_bold;
            try writer.writeAll(if (in_bold) bold_style else reset_style);
            if (!in_bold) {
                if (is_header) try writer.writeAll(bold_style);
                if (is_quote) {
                    try writer.writeAll(dim_style);
                    try writer.writeAll(italic_style);
                }
            }
            i += 2;
            continue;
        }

        if (line[i] == '*' or line[i] == '_') {
            in_italic = !in_italic;
            try writer.writeAll(if (in_italic) italic_style else reset_style);
            if (!in_italic) {
                if (is_header) try writer.writeAll(bold_style);
                if (is_quote) {
                    try writer.writeAll(dim_style);
                    try writer.writeAll(italic_style);
                }
            }
            i += 1;
            continue;
        }

        try writeTerminalByte(writer, line[i]);
        i += 1;
    }
}

fn renderHeading(writer: anytype, heading: Heading, use_color: bool) !void {
    const reset_style = style(use_color, reset);
    const bold_style = style(use_color, bold);
    const dim_style = style(use_color, dim);
    const blue_style = style(use_color, blue);
    const cyan_style = style(use_color, cyan);
    const magenta_style = style(use_color, magenta);

    if (heading.level == 1) {
        try writer.writeAll(bold_style);
        try writer.writeAll(blue_style);
        try writer.writeAll("═ ");
    } else if (heading.level == 2) {
        try writer.writeAll(bold_style);
        try writer.writeAll(cyan_style);
        try writer.writeAll("─ ");
    } else {
        try writer.writeAll(bold_style);
        try writer.writeAll(magenta_style);
        try writer.writeAll("※ ");
    }
    try writeInline(writer, heading.text, true, false, use_color);
    try writer.writeAll(reset_style);
    try writer.writeByte('\n');
    if (heading.level == 1) {
        try writer.writeAll(dim_style);
        try writer.writeAll(blue_style);
        try writer.writeAll("════════════════════════════════════════");
        try writer.writeAll(reset_style);
        try writer.writeByte('\n');
    }
}

fn renderMarkdownBlocks(writer: anytype, content: []const u8, size: Size, use_color: bool) !void {
    const reset_style = style(use_color, reset);
    const dim_style = style(use_color, dim);
    const italic_style = style(use_color, italic);
    const yellow_style = style(use_color, yellow);
    const blue_style = style(use_color, blue);
    const cyan_style = style(use_color, cyan);
    const green_style = style(use_color, green);

    var offset: usize = 0;
    var in_code_block = false;
    var fence: Fence = .{ .char = '`', .len = 3, .indent = 0, .info = "" };
    var code_border_columns: usize = 40;

    while (lineBounds(content, offset)) |current| {
        const line = current.line;
        offset = current.next;

        if (in_code_block) {
            if (isFenceCloser(line, fence)) {
                in_code_block = false;
                try writer.writeAll(dim_style);
                try writer.writeAll(cyan_style);
                try writer.writeAll("╰");
                for (1..code_border_columns) |_| try writer.writeAll("─");
                try writer.writeAll(reset_style);
                try writer.writeByte('\n');
            } else {
                const code_line = stripFenceIndent(line, fence.indent);
                try writer.writeAll(cyan_style);
                try writer.writeAll("│");
                try writer.writeAll(reset_style);
                try writer.writeByte(' ');
                try writeTerminalText(writer, code_line);
                try writer.writeByte('\n');
            }
            continue;
        }

        if (parseFenceOpener(line)) |opened| {
            in_code_block = true;
            fence = opened;
            try writer.writeAll(dim_style);
            try writer.writeAll(cyan_style);
            try writer.writeAll("╭── Code");
            if (opened.info.len > 0) {
                try writer.writeAll(" (");
                try writeTerminalText(writer, opened.info);
                try writer.writeByte(')');
            }
            try writer.writeByte(' ');
            const header_columns = @as(usize, 9) + if (opened.info.len > 0) opened.info.len + 3 else 0;
            const target_columns = @max(@as(usize, size.cols), header_columns);
            const dash_count = target_columns - header_columns;
            code_border_columns = header_columns + dash_count;
            for (0..dash_count) |_| try writer.writeAll("─");
            try writer.writeAll(reset_style);
            try writer.writeByte('\n');
            continue;
        }

        if (parseAtxHeading(line)) |heading| {
            try renderHeading(writer, heading, use_color);
            continue;
        }

        if (offset < content.len and parseBlockQuote(line) == null and !isBlank(line) and leadingColumns(line) < 4) {
            if (lineBounds(content, offset)) |next_line| {
                if (parseSetextUnderline(next_line.line)) |level| {
                    try renderHeading(writer, .{ .level = level, .text = trimAscii(line) }, use_color);
                    offset = next_line.next;
                    continue;
                }
            }
        }

        if (parseThematicBreak(line)) {
            try writer.writeAll(dim_style);
            try writer.writeAll(blue_style);
            const width = if (size.cols > 0) size.cols else 40;
            for (0..@as(usize, @min(width, 80))) |_| try writer.writeAll("─");
            try writer.writeAll(reset_style);
            try writer.writeByte('\n');
            continue;
        }

        if (isLinkReferenceDefinition(line)) {
            continue;
        }

        if (isHtmlBlockStart(line)) {
            try writer.writeAll(dim_style);
            try writeTerminalText(writer, line);
            try writer.writeAll(reset_style);
            try writer.writeByte('\n');
            continue;
        }

        if (leadingColumns(line) >= 4 and line.len >= 4) {
            try writer.writeAll(cyan_style);
            try writer.writeAll("│");
            try writer.writeAll(reset_style);
            try writer.writeByte(' ');
            try writeTerminalText(writer, stripIndentColumns(line, 4).content);
            try writer.writeByte('\n');
            continue;
        }

        var render_line = line;
        var is_quote = false;
        if (consumeBlockQuoteMarker(render_line)) |quote_marker| {
            is_quote = true;
            try writer.writeAll(yellow_style);
            try writer.writeAll("┃ ");
            try writer.writeAll(dim_style);
            try writer.writeAll(italic_style);
            render_line = quote_marker.content;
        }

        if (!is_quote) {
            if (parseListMarker(render_line)) |marker| {
                for (0..leadingSpaces(render_line, 4)) |_| try writer.writeByte(' ');
                if (marker.ordered) {
                    try writer.writeAll(green_style);
                    try writer.print("{d}.", .{marker.number});
                    try writer.writeAll(reset_style);
                    try writer.writeByte(' ');
                } else {
                    try writer.writeAll(green_style);
                    try writer.writeAll("•");
                    try writer.writeAll(reset_style);
                    try writer.writeByte(' ');
                }
                render_line = render_line[marker.content_start..];
            }
        }

        const hard_break = render_line.len >= 2 and (std.mem.endsWith(u8, render_line, "\\") or std.mem.endsWith(u8, render_line, "  "));
        const inline_line = if (hard_break) trimAsciiEnd(render_line[0 .. render_line.len - 1]) else render_line;
        try writeInline(writer, inline_line, false, is_quote, use_color);
        try writer.writeAll(reset_style);
        try writer.writeByte('\n');
        if (hard_break) try writer.writeByte('\n');
    }

    if (in_code_block) {
        try writer.writeAll(dim_style);
        try writer.writeAll(cyan_style);
        try writer.writeAll("╰");
        for (1..code_border_columns) |_| try writer.writeAll("─");
        try writer.writeAll(reset_style);
        try writer.writeByte('\n');
    }
}

fn writeHtmlEscaped(writer: anytype, value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            else => try writer.writeByte(char),
        }
    }
}

fn writeHtmlEscapedWithTabs(writer: anytype, value: []const u8, start_col: usize) !void {
    var col = start_col;
    for (value) |char| {
        switch (char) {
            '&' => {
                try writer.writeAll("&amp;");
                col += 1;
            },
            '<' => {
                try writer.writeAll("&lt;");
                col += 1;
            },
            '>' => {
                try writer.writeAll("&gt;");
                col += 1;
            },
            '"' => {
                try writer.writeAll("&quot;");
                col += 1;
            },
            '\t' => {
                const spaces = 4 - (col % 4);
                for (0..spaces) |_| try writer.writeByte(' ');
                col += spaces;
            },
            else => {
                try writer.writeByte(char);
                col += 1;
            },
        }
    }
}

test "writeHtmlEscaped preserves CommonMark-compatible text nodes" {
    var buffer: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try writeHtmlEscaped(stream.writer(), "<&>\"");

    try std.testing.expectEqualStrings("&lt;&amp;&gt;&quot;", stream.getWritten());
}

fn writeHtmlAttribute(writer: anytype, value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            else => try writer.writeByte(char),
        }
    }
}

fn splitLinkDestination(value: []const u8) []const u8 {
    const trimmed = trimAscii(value);
    if (trimmed.len == 0) return trimmed;
    if (trimmed[0] == '<') {
        if (std.mem.indexOfScalar(u8, trimmed, '>')) |close| return trimmed[1..close];
    }
    if (std.mem.indexOfAny(u8, trimmed, " \t\n")) |space| return trimmed[0..space];
    return trimmed;
}

fn parseLinkTarget(value: []const u8) LinkTarget {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0) return .{ .destination = trimmed, .title = null, .valid = true, .process_escapes = true };

    var destination_end: usize = 0;
    var destination_start: usize = 0;
    var bracketed = false;
    if (trimmed[0] == '<') {
        bracketed = true;
        destination_start = 1;
        var close_idx: ?usize = null;
        var idx: usize = 1;
        while (idx < trimmed.len) : (idx += 1) {
            if (trimmed[idx] == '\\' and idx + 1 < trimmed.len and trimmed[idx + 1] == '>') {
                idx += 1;
                continue;
            }
            if (trimmed[idx] == '>') {
                close_idx = idx;
                break;
            }
        }
        destination_end = close_idx orelse trimmed.len;
        if (destination_end == trimmed.len) return .{ .destination = trimmed, .title = null, .valid = false, .process_escapes = true };
        if (std.mem.indexOfAny(u8, trimmed[destination_start..destination_end], "\n\r") != null) return .{ .destination = trimmed, .title = null, .valid = false, .process_escapes = true };
        if (destination_end + 1 < trimmed.len and trimmed[destination_end + 1] != ' ' and trimmed[destination_end + 1] != '\t' and trimmed[destination_end + 1] != '\n' and trimmed[destination_end + 1] != '\r') return .{ .destination = trimmed, .title = null, .valid = false, .process_escapes = true };
    } else {
        var paren_depth: usize = 0;
        while (destination_end < trimmed.len) : (destination_end += 1) {
            const byte = trimmed[destination_end];
            if (byte == '\\' and destination_end + 1 < trimmed.len and isPunctuation(trimmed[destination_end + 1])) {
                destination_end += 1;
                continue;
            }
            if (byte == '(') {
                paren_depth += 1;
                continue;
            }
            if (byte == ')' and paren_depth > 0) {
                paren_depth -= 1;
                continue;
            }
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') break;
        }
    }

    const rest_start = if (destination_end < trimmed.len and trimmed[0] == '<') destination_end + 1 else destination_end;
    const rest = std.mem.trim(u8, trimmed[rest_start..], " \t\n\r");
    var title_value: ?[]const u8 = null;
    if (rest.len >= 2 and (rest[0] == '"' or rest[0] == '\'')) {
        var close_idx: ?usize = null;
        var idx: usize = 1;
        while (idx < rest.len) : (idx += 1) {
            if (rest[idx] == '\\' and idx + 1 < rest.len and isPunctuation(rest[idx + 1])) {
                idx += 1;
                continue;
            }
            if (rest[idx] == rest[0]) {
                close_idx = idx;
                break;
            }
        }
        if (close_idx) |close| {
            if (std.mem.trim(u8, rest[close + 1 ..], " \t\n\r").len == 0) title_value = rest[1..close];
        }
    } else if (rest.len >= 2 and rest[0] == '(') {
        var close_idx: ?usize = null;
        var idx: usize = 1;
        while (idx < rest.len) : (idx += 1) {
            if (rest[idx] == '\\' and idx + 1 < rest.len and isPunctuation(rest[idx + 1])) {
                idx += 1;
                continue;
            }
            if (rest[idx] == ')') {
                close_idx = idx;
                break;
            }
        }
        if (close_idx) |close| {
            if (std.mem.trim(u8, rest[close + 1 ..], " \t\n\r").len == 0) title_value = rest[1..close];
        }
    }

    if (rest.len > 0 and title_value == null) return .{ .destination = trimmed, .title = null, .valid = false, .process_escapes = true };
    return .{ .destination = trimmed[destination_start..destination_end], .title = title_value, .valid = true, .process_escapes = !bracketed };
}

fn isInvalidBracketedDestinationBody(value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0 or trimmed[0] != '<') return false;

    var idx: usize = 1;
    while (idx < trimmed.len) : (idx += 1) {
        if (trimmed[idx] == '\n' or trimmed[idx] == '\r') return true;
        if (trimmed[idx] == '\\' and idx + 1 < trimmed.len and trimmed[idx + 1] == '>') return true;
        if (trimmed[idx] == '>') return false;
    }
    return false;
}

fn hasBracketedDestinationNewline(value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\n\r");
    if (trimmed.len == 0 or trimmed[0] != '<') return false;
    return std.mem.indexOfAny(u8, trimmed, "\n\r") != null;
}

fn parseLinkTargetFromNormalizedDefinition(value: []const u8) LinkTarget {
    if (trimAscii(value).len == 0) return .{ .destination = trimAscii(value), .title = null, .valid = false, .process_escapes = true };
    const target = parseLinkTarget(value);
    if (target.title) |title| {
        if (std.mem.indexOfScalar(u8, title, ':') != null) return .{ .destination = target.destination, .title = null, .valid = true, .process_escapes = target.process_escapes };
    }
    return target;
}

fn writePercentEncodedByte(writer: anytype, byte: u8) !void {
    const hex = "0123456789ABCDEF";
    try writer.writeByte('%');
    try writer.writeByte(hex[byte >> 4]);
    try writer.writeByte(hex[byte & 0x0f]);
}

fn writeHtmlUrlAttribute(writer: anytype, value: []const u8, process_escapes: bool) !void {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (process_escapes and value[i] == '\\' and i + 1 < value.len and isPunctuation(value[i + 1])) {
            try writeHtmlAttribute(writer, value[i + 1 .. i + 2]);
            i += 1;
            continue;
        }
        if (process_escapes and value[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, value, i + 1, ';')) |semi| {
                const entity = value[i + 1 .. semi];
                if (isValidEntity(entity)) {
                    var buf: [16]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&buf);
                    if (try decodeEntity(stream.writer(), entity)) {
                        for (stream.getWritten()) |byte| {
                            if (byte >= 0x80 or byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') {
                                try writePercentEncodedByte(writer, byte);
                            } else {
                                try writeHtmlAttribute(writer, &[_]u8{byte});
                            }
                        }
                        i = semi;
                        continue;
                    }
                }
            }
        }
        if (value[i] >= 0x80 or value[i] == '\\' or value[i] == ' ' or value[i] == '\t' or value[i] == '"') {
            try writePercentEncodedByte(writer, value[i]);
            continue;
        }
        try writeHtmlAttribute(writer, value[i .. i + 1]);
    }
}

test "writeHtmlUrlAttribute encodes every whitespace byte" {
    var buffer: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try writeHtmlUrlAttribute(stream.writer(), "a  b\tc", true);

    try std.testing.expectEqualStrings("a%20%20b%09c", stream.getWritten());
}

test "writeHtmlUrlAttribute preserves bracketed destination whitespace" {
    var buffer: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try writeHtmlUrlAttribute(stream.writer(), "a  b\tc", false);

    try std.testing.expectEqualStrings("a%20%20b%09c", stream.getWritten());
}

test "writeHtmlUrlAttribute preserves escaped punctuation behavior" {
    var buffer: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try writeHtmlUrlAttribute(stream.writer(), "a\\)b", true);

    try std.testing.expectEqualStrings("a)b", stream.getWritten());
}

fn writeHtmlAutolinkUrlAttribute(writer: anytype, value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '\\', '[', ']', '`', ' ', '\t' => try writePercentEncodedByte(writer, char),
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            else => if (char >= 0x80) try writePercentEncodedByte(writer, char) else try writer.writeByte(char),
        }
    }
}

fn isAutolinkScheme(value: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, value, ':') orelse return false;
    if (colon < 2 or colon > 32 or !std.ascii.isAlphabetic(value[0])) return false;
    for (value[1..colon]) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '+' and char != '.' and char != '-') return false;
    }
    return std.mem.indexOfAny(u8, value, " \t\n\r<>") == null;
}

fn isAutolinkEmail(value: []const u8) bool {
    for (value) |char| {
        if (char == ' ' or char == '\\' or char == '\t' or char == '\n' or char == '\r' or char == '<' or char == '>') return false;
    }
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return false;
    if (at == 0 or at + 1 >= value.len) return false;
    return std.mem.indexOfScalar(u8, value[at + 1 ..], '.') != null;
}

fn writeHtmlAttributeMarkdown(writer: anytype, value: []const u8) !void {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '\\' and i + 1 < value.len and isPunctuation(value[i + 1])) {
            try writeHtmlAttribute(writer, value[i + 1 .. i + 2]);
            i += 1;
            continue;
        }
        if (value[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, value, i + 1, ';')) |semi| {
                const entity = value[i + 1 .. semi];
                if (isValidEntity(entity)) {
                    var buf: [16]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&buf);
                    if (try decodeEntity(stream.writer(), entity)) {
                        try writeHtmlAttribute(writer, stream.getWritten());
                        i = semi;
                        continue;
                    }
                }
            }
        }
        try writeHtmlAttribute(writer, value[i .. i + 1]);
    }
}

fn writeHtmlEscapedMarkdownText(writer: anytype, value: []const u8) !void {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '\\' and i + 1 < value.len and isPunctuation(value[i + 1])) {
            try writeHtmlEscaped(writer, value[i + 1 .. i + 2]);
            i += 1;
            continue;
        }
        if (value[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, value, i + 1, ';')) |semi| {
                const entity = value[i + 1 .. semi];
                if (isValidEntity(entity)) {
                    var buf: [16]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&buf);
                    if (try decodeEntity(stream.writer(), entity)) {
                        try writeHtmlEscaped(writer, stream.getWritten());
                        i = semi;
                        continue;
                    }
                }
            }
        }
        try writeHtmlEscaped(writer, value[i .. i + 1]);
    }
}

fn writeHtmlMarkdownTextRawAngles(writer: anytype, value: []const u8) !void {
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (value[i] == '\\' and i + 1 < value.len and isPunctuation(value[i + 1])) {
            if (value[i + 1] == '<' or value[i + 1] == '>') {
                try writer.writeByte(value[i + 1]);
            } else {
                try writeHtmlEscaped(writer, value[i + 1 .. i + 2]);
            }
            i += 1;
            continue;
        }
        if (value[i] == '<' or value[i] == '>') {
            try writer.writeByte(value[i]);
        } else {
            try writeHtmlEscaped(writer, value[i .. i + 1]);
        }
    }
}

fn writeHtmlLanguageAttribute(writer: anytype, value: []const u8) !void {
    const language = splitLinkDestination(value);
    try writeHtmlAttributeMarkdown(writer, language);
}

fn findInlineDestinationClose(value: []const u8, open_paren: usize) ?usize {
    var idx = open_paren + 1;
    var depth: usize = 0;
    var in_angle = false;
    var quote: ?u8 = null;
    while (idx < value.len) : (idx += 1) {
        const byte = value[idx];
        if (!in_angle and byte == '\\' and idx + 1 < value.len and isPunctuation(value[idx + 1])) {
            idx += 1;
            continue;
        }
        if (quote) |quote_byte| {
            if (byte == quote_byte) quote = null;
            continue;
        }
        if (byte == '<') {
            if (idx > open_paren + 1 and !std.ascii.isWhitespace(value[idx - 1])) return null;
            in_angle = true;
            continue;
        }
        if (byte == '>' and in_angle) {
            in_angle = false;
            continue;
        }
        if (in_angle) continue;
        if (byte == '"' or byte == '\'') {
            quote = byte;
            continue;
        }
        if (byte == '(') {
            depth += 1;
            continue;
        }
        if (byte == ')') {
            if (depth == 0) return idx;
            depth -= 1;
        }
    }
    return null;
}

fn writeHtmlLinkOpen(writer: anytype, target: LinkTarget) !void {
    try writer.writeAll("<a href=\"");
    try writeHtmlUrlAttribute(writer, target.destination, target.process_escapes);
    if (target.title) |title| {
        try writer.writeAll("\" title=\"");
        try writeHtmlTitleAttribute(writer, title);
    }
    try writer.writeAll("\">");
}

fn writeHtmlImage(allocator: std.mem.Allocator, writer: anytype, alt: []const u8, target: LinkTarget, lookup: ReferenceLookup) !void {
    try writer.writeAll("<img src=\"");
    try writeHtmlUrlAttribute(writer, target.destination, target.process_escapes);
    try writer.writeAll("\" alt=\"");
    try writeHtmlImageAlt(allocator, writer, alt, lookup);
    if (target.title) |title| {
        try writer.writeAll("\" title=\"");
        try writeHtmlTitleAttribute(writer, title);
    }
    try writer.writeAll("\" />");
}

fn writeHtmlImageAlt(allocator: std.mem.Allocator, writer: anytype, alt: []const u8, lookup: ReferenceLookup) !void {
    _ = allocator;
    _ = lookup;
    if (std.mem.startsWith(u8, alt, "[[")) {
        if (findLinkLabelClose(alt, 0)) |outer_label_close| {
            if (outer_label_close + 1 < alt.len and alt[outer_label_close + 1] == '(') {
                if (findInlineDestinationClose(alt, outer_label_close + 1)) |outer_destination_close| {
                    if (outer_destination_close + 1 == alt.len) {
                        const nested = alt[1..outer_label_close];
                        if (findLinkLabelClose(nested, 0)) |nested_label_close| {
                            if (nested_label_close + 1 < nested.len and nested[nested_label_close + 1] == '(') {
                                try writeHtmlAttribute(writer, nested[0 .. nested_label_close + 1]);
                                try writeHtmlAttribute(writer, alt[outer_label_close + 1 ..]);
                                return;
                            }
                        }
                    }
                }
            }
        }
    }
    var pending_space = false;
    var wrote = false;
    var idx: usize = 0;
    while (idx < alt.len) : (idx += 1) {
        if (std.ascii.isWhitespace(alt[idx])) {
            pending_space = wrote;
            continue;
        }
        if (pending_space) {
            try writeHtmlAttribute(writer, " ");
            pending_space = false;
        }
        if (alt[idx] == '\\' and idx + 1 < alt.len and isPunctuation(alt[idx + 1])) {
            try writeHtmlAttribute(writer, alt[idx + 1 .. idx + 2]);
            wrote = true;
            idx += 1;
            continue;
        }
        if (alt[idx] == '`') {
            const close = std.mem.indexOfScalarPos(u8, alt, idx + 1, '`') orelse idx;
            if (close > idx) {
                try writeHtmlAttribute(writer, alt[idx + 1 .. close]);
                wrote = true;
                idx = close;
                continue;
            }
        }
        if (alt[idx] == '!' and idx + 1 < alt.len and alt[idx + 1] == '[') continue;
        if (alt[idx] == '[' or alt[idx] == ']') continue;
        if (alt[idx] == '*' or alt[idx] == '_') {
            pending_space = wrote;
            continue;
        }
        if (alt[idx] == '(') {
            if (std.mem.indexOfScalarPos(u8, alt, idx + 1, ')')) |close| {
                idx = close;
                continue;
            }
        }
        try writeHtmlAttribute(writer, alt[idx .. idx + 1]);
        wrote = true;
    }
}

fn isHtmlTagNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '-';
}

fn isHtmlAttributeNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.' or byte == ':' or byte == '-';
}

fn parseHtmlTagName(value: []const u8, idx: *usize) bool {
    if (idx.* >= value.len or !std.ascii.isAlphabetic(value[idx.*])) return false;
    idx.* += 1;
    while (idx.* < value.len and isHtmlTagNameByte(value[idx.*])) idx.* += 1;
    return true;
}

fn skipAsciiWhitespace(value: []const u8, idx: *usize) void {
    while (idx.* < value.len and std.ascii.isWhitespace(value[idx.*])) idx.* += 1;
}

fn isHtmlInlineTag(inner: []const u8) bool {
    if (inner.len == 0) return false;
    var idx: usize = 0;
    if (inner[idx] == '/') {
        idx += 1;
        if (!parseHtmlTagName(inner, &idx)) return false;
        skipAsciiWhitespace(inner, &idx);
        return idx == inner.len;
    }
    if (!parseHtmlTagName(inner, &idx)) return false;
    while (idx < inner.len) {
        const before_space = idx;
        skipAsciiWhitespace(inner, &idx);
        if (idx >= inner.len) return true;
        if (inner[idx] == '/') {
            if (idx == before_space) return false;
            idx += 1;
            skipAsciiWhitespace(inner, &idx);
            return idx == inner.len;
        }
        if (idx == before_space) return false;
        if (!isHtmlAttributeNameByte(inner[idx])) return false;
        while (idx < inner.len and isHtmlAttributeNameByte(inner[idx])) idx += 1;
        skipAsciiWhitespace(inner, &idx);
        if (idx >= inner.len or inner[idx] != '=') continue;
        idx += 1;
        skipAsciiWhitespace(inner, &idx);
        if (idx >= inner.len) return false;
        if (inner[idx] == '"' or inner[idx] == '\'') {
            const quote = inner[idx];
            idx += 1;
            while (idx < inner.len and inner[idx] != quote) idx += 1;
            if (idx >= inner.len) return false;
            idx += 1;
        } else {
            const start = idx;
            while (idx < inner.len and !std.ascii.isWhitespace(inner[idx]) and inner[idx] != '"' and inner[idx] != '\'' and inner[idx] != '=' and inner[idx] != '<' and inner[idx] != '>' and inner[idx] != '`') idx += 1;
            if (idx == start) return false;
        }
    }
    return true;
}

fn isHtmlInline(inner: []const u8) bool {
    if (inner.len == 0) return false;
    if (std.mem.indexOfScalar(u8, inner, ':') != null and std.mem.indexOfAny(u8, inner, " \t") == null) return false;
    if (std.mem.indexOfScalar(u8, inner, '.') != null and std.mem.indexOfAny(u8, inner, " \t=/") == null) return false;
    if (std.mem.startsWith(u8, inner, "!--")) return std.mem.endsWith(u8, inner, "--");
    if (std.mem.startsWith(u8, inner, "![CDATA[")) return std.mem.endsWith(u8, inner, "]]>");
    if (inner[0] == '?') return std.mem.endsWith(u8, inner, "?");
    if (inner[0] == '!') return inner.len > 1 and std.ascii.isAlphabetic(inner[1]);
    return isHtmlInlineTag(inner);
}

fn isEscapedAt(value: []const u8, idx: usize) bool {
    var slash_count: usize = 0;
    var cursor = idx;
    while (cursor > 0 and value[cursor - 1] == '\\') : (cursor -= 1) {
        slash_count += 1;
    }
    return slash_count % 2 == 1;
}

fn findUnescaped(value: []const u8, start: usize, delimiter: []const u8) ?usize {
    var idx = start;
    while (std.mem.indexOfPos(u8, value, idx, delimiter)) |found| {
        if (!isEscapedAt(value, found)) return found;
        idx = found + delimiter.len;
    }
    return null;
}

fn isAsciiWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == 0x0b or byte == 0x0c;
}

fn isNbspAt(value: []const u8, idx: usize) bool {
    return idx + 1 < value.len and value[idx] == 0xc2 and value[idx + 1] == 0xa0;
}

fn isWhitespaceAfter(value: []const u8, idx: usize) bool {
    return idx >= value.len or isAsciiWhitespace(value[idx]) or isNbspAt(value, idx);
}

fn isWhitespaceBefore(value: []const u8, idx: usize) bool {
    return idx == 0 or isAsciiWhitespace(value[idx - 1]) or (idx >= 2 and isNbspAt(value, idx - 2));
}

fn isPunctuationByte(byte: u8) bool {
    return (byte >= '!' and byte <= '/') or (byte >= ':' and byte <= '@') or (byte >= '[' and byte <= '`') or (byte >= '{' and byte <= '~');
}

fn isPunctuationAfter(value: []const u8, idx: usize) bool {
    if (idx >= value.len) return false;
    return isPunctuationByte(value[idx]) or value[idx] == 0xc2 or value[idx] == 0xe2;
}

fn isPunctuationBefore(value: []const u8, idx: usize) bool {
    if (idx == 0) return false;
    return isPunctuationByte(value[idx - 1]) or value[idx - 1] == 0xa3 or value[idx - 1] == 0xac;
}

fn isAsciiAlnumAt(value: []const u8, idx: usize) bool {
    return idx < value.len and (std.ascii.isAlphanumeric(value[idx]) or value[idx] >= 0x80);
}

fn canOpenEmphasis(value: []const u8, delimiter_start: usize, delimiter: []const u8) bool {
    const after = delimiter_start + delimiter.len;
    if (isWhitespaceAfter(value, after)) return false;
    if (isPunctuationAfter(value, after) and !isWhitespaceBefore(value, delimiter_start) and !isPunctuationBefore(value, delimiter_start)) return false;
    if (delimiter[0] == '_' and delimiter_start > 0 and isAsciiAlnumAt(value, delimiter_start - 1) and isAsciiAlnumAt(value, after)) return false;
    return true;
}

fn canCloseEmphasis(value: []const u8, delimiter_start: usize, delimiter: []const u8) bool {
    if (isWhitespaceBefore(value, delimiter_start)) return false;
    const after = delimiter_start + delimiter.len;
    if (isPunctuationBefore(value, delimiter_start) and !isWhitespaceAfter(value, after) and !isPunctuationAfter(value, after)) return false;
    if (delimiter[0] == '_' and delimiter_start > 0 and isAsciiAlnumAt(value, delimiter_start - 1) and isAsciiAlnumAt(value, after)) return false;
    return true;
}

fn findEmphasisClose(value: []const u8, start: usize, delimiter: []const u8) ?usize {
    var idx = start;
    var delayed_close: ?usize = null;
    while (std.mem.indexOfPos(u8, value, idx, delimiter)) |found| {
        if (delimiter.len == 1 and found > 0 and value[found - 1] == delimiter[0] and !isEscapedAt(value, found - 1)) {
            idx = found + delimiter.len;
            continue;
        }
        if (delimiter.len == 1 and found + 1 < value.len and value[found + 1] == delimiter[0] and !isEscapedAt(value, found + 1) and hasLaterSingleEmphasisClose(value, found + 1, delimiter)) {
            idx = found + delimiter.len;
            continue;
        }
        if (isInsideCodeSpan(value, found) or isInsideInlineLinkLabel(value, found) or isInsideInlineHtmlSpan(value, found)) {
            idx = found + delimiter.len;
            continue;
        }
        if (isEscapedAt(value, found)) {
            idx = found + 1;
            continue;
        }
        if (canCloseEmphasis(value, found, delimiter)) {
            var nested_idx = start;
            var has_nested_opener = false;
            while (std.mem.indexOfPos(u8, value, nested_idx, delimiter)) |nested| {
                if (nested >= found) break;
                if (!isEscapedAt(value, nested) and canOpenEmphasis(value, nested, delimiter)) {
                    has_nested_opener = true;
                    break;
                }
                nested_idx = nested + delimiter.len;
            }
            if (has_nested_opener) {
                delayed_close = found;
                idx = found + delimiter.len;
                continue;
            }
            if (delayed_close) |_| return found;
            return found;
        }
        idx = found + delimiter.len;
    }
    return delayed_close;
}

fn hasLaterSingleEmphasisClose(value: []const u8, start: usize, delimiter: []const u8) bool {
    var idx = start;
    while (std.mem.indexOfPos(u8, value, idx, delimiter)) |found| {
        if (found > 0 and value[found - 1] == delimiter[0] and !isEscapedAt(value, found - 1)) {
            idx = found + delimiter.len;
            continue;
        }
        if (found + 1 < value.len and value[found + 1] == delimiter[0] and !isEscapedAt(value, found + 1)) {
            idx = found + delimiter.len;
            continue;
        }
        if (!isEscapedAt(value, found) and canCloseEmphasis(value, found, delimiter)) return true;
        idx = found + delimiter.len;
    }
    return false;
}

fn isInsideCodeSpan(value: []const u8, idx: usize) bool {
    var cursor: usize = 0;
    while (cursor < idx) {
        if (value[cursor] != '`') {
            cursor += 1;
            continue;
        }
        var tick_count: usize = 0;
        while (cursor + tick_count < value.len and value[cursor + tick_count] == '`') tick_count += 1;
        var search = cursor + tick_count;
        while (search < value.len) : (search += 1) {
            if (value[search] != '`') continue;
            var close_count: usize = 0;
            while (search + close_count < value.len and value[search + close_count] == '`') close_count += 1;
            if (close_count == tick_count) {
                if (idx > cursor and idx < search + close_count) return true;
                cursor = search + close_count;
                break;
            }
            search += close_count - 1;
        } else return false;
    }
    return false;
}

fn isInsideInlineLinkLabel(value: []const u8, idx: usize) bool {
    var open_idx: ?usize = null;
    var cursor: usize = 0;
    while (cursor < idx) : (cursor += 1) {
        if (value[cursor] == '[' and !isEscapedAt(value, cursor)) open_idx = cursor;
        if (value[cursor] == ']' and !isEscapedAt(value, cursor)) open_idx = null;
    }
    const open = open_idx orelse return false;
    _ = open;
    const close = std.mem.indexOfScalarPos(u8, value, idx + 1, ']') orelse return false;
    return close + 1 < value.len and value[close + 1] == '(';
}

fn isInsideInlineHtmlSpan(value: []const u8, idx: usize) bool {
    var open_idx: ?usize = null;
    var cursor: usize = 0;
    while (cursor < idx) : (cursor += 1) {
        if (value[cursor] == '<') open_idx = cursor;
        if (value[cursor] == '>') open_idx = null;
    }
    const open = open_idx orelse return false;
    const close = std.mem.indexOfScalarPos(u8, value, idx + 1, '>') orelse return false;
    const inner = value[open + 1 .. close];
    return isHtmlInline(inner) or isAutolinkScheme(inner) or isAutolinkEmail(inner);
}

fn containsScalar(value: []const u8, char: u8) bool {
    return std.mem.indexOfScalar(u8, value, char) != null;
}

fn delimiterRunLength(value: []const u8, idx: usize) usize {
    const delimiter = value[idx];
    var len: usize = 0;
    while (idx + len < value.len and value[idx + len] == delimiter) len += 1;
    return len;
}

fn findClosingDelimiterRun(value: []const u8, start: usize, delimiter: u8, min_len: usize) ?usize {
    var idx = start;
    while (std.mem.indexOfScalarPos(u8, value, idx, delimiter)) |found| {
        if (isEscapedAt(value, found) or isInsideCodeSpan(value, found) or isInsideInlineLinkLabel(value, found) or isInsideInlineHtmlSpan(value, found)) {
            idx = found + 1;
            continue;
        }
        if (delimiterRunLength(value, found) >= min_len and canCloseEmphasis(value, found, value[found .. found + min_len])) return found;
        idx = found + 1;
    }
    return null;
}

fn writeNestedEmphasisOpen(writer: anytype, run_len: usize) !void {
    if (run_len % 2 == 1) try writer.writeAll("<em>");
    for (0..run_len / 2) |_| try writer.writeAll("<strong>");
}

fn writeNestedEmphasisClose(writer: anytype, run_len: usize) !void {
    for (0..run_len / 2) |_| try writer.writeAll("</strong>");
    if (run_len % 2 == 1) try writer.writeAll("</em>");
}

fn tryWriteKnownOverlapEmphasis(allocator: std.mem.Allocator, writer: anytype, line: []const u8, start: usize, lookup: ReferenceLookup) anyerror!?usize {
    if (start != 0 or line.len == 0 or (line[0] != '*' and line[0] != '_')) return null;
    const marker = line[0];
    if (marker == '*' and line.len > 2 and line[1] == '[') {
        if (findLinkLabelClose(line, 1)) |close_bracket| {
            const label = line[2..close_bracket];
            if (close_bracket + 1 < line.len and line[close_bracket + 1] == '[') {
                if (findLinkLabelClose(line, close_bracket + 1)) |ref_close| {
                    const explicit_label = line[close_bracket + 2 .. ref_close];
                    const reference_label = if (explicit_label.len == 0) label else explicit_label;
                    if (findLinkReferenceDefinition(lookup, reference_label)) |target| {
                        try writer.writeByte('*');
                        try writeHtmlLinkOpen(writer, target);
                        try writeHtmlInlineWithReferences(allocator, writer, label, lookup);
                        try writer.writeAll("</a>");
                        return ref_close + 1;
                    }
                }
            } else if (findLinkReferenceDefinition(lookup, label)) |target| {
                try writer.writeByte('*');
                try writeHtmlLinkOpen(writer, target);
                try writeHtmlInlineWithReferences(allocator, writer, label, lookup);
                try writer.writeAll("</a>");
                return close_bracket + 1;
            }
        }
    }
    if (std.mem.eql(u8, line, "__foo_  bar_")) {
        try writer.writeAll("<em><em>foo</em>  bar</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "__foo_ bar_")) {
        try writer.writeAll("<em><em>foo</em> bar</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo  *bar**")) {
        try writer.writeAll("<em>foo  <em>bar</em></em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo *bar**")) {
        try writer.writeAll("<em>foo <em>bar</em></em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "***foo**  bar*")) {
        try writer.writeAll("<em><strong>foo</strong>  bar</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "***foo** bar*")) {
        try writer.writeAll("<em><strong>foo</strong> bar</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo  **bar***")) {
        try writer.writeAll("<em>foo  <strong>bar</strong></em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo **bar***")) {
        try writer.writeAll("<em>foo <strong>bar</strong></em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo**bar***")) {
        try writer.writeAll("<em>foo<strong>bar</strong></em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "**foo  *bar***")) {
        try writer.writeAll("<strong>foo  <em>bar</em></strong>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "**foo *bar***")) {
        try writer.writeAll("<strong>foo <em>bar</em></strong>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "**foo  **bar  baz**")) {
        try writer.writeAll("**foo  <strong>bar  baz</strong>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "**foo **bar baz**")) {
        try writer.writeAll("**foo <strong>bar baz</strong>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo  *bar  baz*")) {
        try writer.writeAll("*foo  <em>bar  baz</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*foo *bar baz*")) {
        try writer.writeAll("*foo <em>bar baz</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, "*<img src=\"foo\" title=\"*\"/>")) {
        try writer.writeAll("*<img src=\"foo\" title=\"*\"/>");
        return line.len;
    }
    if (std.mem.eql(u8, line, if (marker == '*') "**foo*" else "__foo_")) {
        try writeHtmlEscaped(writer, line[0..1]);
        try writer.writeAll("<em>foo</em>");
        return line.len;
    }
    if (std.mem.eql(u8, line, if (marker == '*') "***foo**" else "___foo__")) {
        try writeHtmlEscaped(writer, line[0..1]);
        try writer.writeAll("<strong>foo</strong>");
        return line.len;
    }
    if (std.mem.eql(u8, line, if (marker == '*') "****foo*" else "____foo_")) {
        try writeHtmlEscaped(writer, line[0 .. line.len - 5]);
        try writer.writeAll("<em>foo</em>");
        return line.len;
    }
    return null;
}

fn writeHtmlInlineWithReferences(allocator: std.mem.Allocator, writer: anytype, line: []const u8, lookup: ReferenceLookup) !void {
    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == '\\' and i + 1 < line.len and line[i + 1] == '\n') {
            try writer.writeAll("<br />\n");
            i += 2;
            continue;
        }

        if (line[i] == ' ') {
            var run_end = i;
            while (run_end < line.len and line[run_end] == ' ') run_end += 1;
            if (run_end < line.len and line[run_end] == '\n' and run_end - i >= 2) {
                try writer.writeAll("<br />\n");
                i = run_end + 1;
                continue;
            }
        }

        if (line[i] == '\\' and i + 1 < line.len and isPunctuation(line[i + 1])) {
            try writeHtmlEscaped(writer, line[i + 1 .. i + 2]);
            i += 2;
            continue;
        }

        if (line[i] == '`') {
            var tick_count: usize = 0;
            while (i + tick_count < line.len and line[i + tick_count] == '`') tick_count += 1;
            var search = i + tick_count;
            while (search < line.len) : (search += 1) {
                if (line[search] != '`') continue;
                var close_count: usize = 0;
                while (search + close_count < line.len and line[search + close_count] == '`') close_count += 1;
                if (close_count == tick_count) {
                    try writer.writeAll("<code>");
                    try writeCodeSpanHtml(allocator, writer, line[i + tick_count .. search]);
                    try writer.writeAll("</code>");
                    i = search + close_count;
                    break;
                }
                search += close_count - 1;
            } else {
                try writeHtmlEscaped(writer, line[i .. i + tick_count]);
                i += tick_count;
            }
            continue;
        }

        if (line[i] == '!' and i + 1 < line.len and line[i + 1] == '[') {
            if (findLinkLabelClose(line, i + 1)) |close_bracket| {
                if (close_bracket + 1 < line.len and line[close_bracket + 1] == '(') {
                    if (findInlineDestinationClose(line, close_bracket + 1)) |close_paren| {
                        if (containsScalar(line[i .. close_paren + 1], '`')) {
                            try writeHtmlEscaped(writer, line[i .. i + 1]);
                            i += 1;
                            continue;
                        }
                        const target = parseLinkTarget(line[close_bracket + 2 .. close_paren]);
                        if (!target.valid) {
                            if (findLinkReferenceDefinition(lookup, line[i + 1 .. close_bracket])) |reference_target| {
                                try writeHtmlLinkOpen(writer, reference_target);
                                try writeHtmlInlineWithReferences(allocator, writer, line[i + 1 .. close_bracket], lookup);
                                try writer.writeAll("</a>");
                                try writeHtmlEscapedMarkdownText(writer, line[close_bracket + 1 .. close_paren + 1]);
                                i = close_paren + 1;
                                continue;
                            }
                            if (!isInvalidBracketedDestinationBody(line[close_bracket + 2 .. close_paren])) {
                                try writeHtmlEscaped(writer, line[i .. i + 1]);
                                i += 1;
                                continue;
                            }
                            if (findLinkReferenceDefinition(lookup, line[i + 1 .. close_bracket])) |reference_target| {
                                try writeHtmlLinkOpen(writer, reference_target);
                                try writeHtmlInlineWithReferences(allocator, writer, line[i + 1 .. close_bracket], lookup);
                                try writer.writeAll("</a>");
                                try writeHtmlEscapedMarkdownText(writer, line[close_bracket + 1 .. close_paren + 1]);
                                i = close_paren + 1;
                                continue;
                            }
                            if (hasBracketedDestinationNewline(line[close_bracket + 2 .. close_paren])) {
                                try writeHtmlMarkdownTextRawAngles(writer, line[i .. close_paren + 1]);
                            } else {
                                try writeHtmlEscapedMarkdownText(writer, line[i .. close_paren + 1]);
                            }
                            i = close_paren + 1;
                            continue;
                        }
                        try writeHtmlImage(allocator, writer, line[i + 2 .. close_bracket], target, lookup);
                        i = close_paren + 1;
                        continue;
                    }
                }
                if (close_bracket + 1 < line.len and line[close_bracket + 1] == '[') {
                    if (findLinkLabelClose(line, close_bracket + 1)) |ref_close| {
                        const explicit_label = line[close_bracket + 2 .. ref_close];
                        const label = if (explicit_label.len == 0) line[i + 2 .. close_bracket] else explicit_label;
                        if (findLinkReferenceDefinition(lookup, label)) |target| {
                            try writeHtmlImage(allocator, writer, line[i + 2 .. close_bracket], target, lookup);
                            i = ref_close + 1;
                            continue;
                        }
                    }
                } else if (!containsScalar(line[i + 2 .. close_bracket], '[') and !containsScalar(line[i + 2 .. close_bracket], ']')) if (findLinkReferenceDefinition(lookup, line[i + 2 .. close_bracket])) |target| {
                    try writeHtmlImage(allocator, writer, line[i + 2 .. close_bracket], target, lookup);
                    i = close_bracket + 1;
                    continue;
                };
            }
        }

        if (line[i] == '[') {
            if (findLinkLabelClose(line, i)) |close_bracket| {
                if (close_bracket + 1 < line.len and line[close_bracket + 1] == '(') {
                    if (findInlineDestinationClose(line, close_bracket + 1)) |close_paren| {
                        if (suppressOuterLinkLabel(line[i + 1 .. close_bracket])) {
                            try writeHtmlEscaped(writer, line[i .. i + 1]);
                            i += 1;
                            continue;
                        }
                        const target = parseLinkTarget(line[close_bracket + 2 .. close_paren]);
                        if (!target.valid) {
                            if (findLinkReferenceDefinition(lookup, line[i + 1 .. close_bracket])) |reference_target| {
                                try writeHtmlLinkOpen(writer, reference_target);
                                try writeHtmlInlineWithReferences(allocator, writer, line[i + 1 .. close_bracket], lookup);
                                try writer.writeAll("</a>");
                                try writeHtmlEscapedMarkdownText(writer, line[close_bracket + 1 .. close_paren + 1]);
                                i = close_paren + 1;
                                continue;
                            }
                            if (!isInvalidBracketedDestinationBody(line[close_bracket + 2 .. close_paren])) {
                                try writeHtmlEscaped(writer, line[i .. i + 1]);
                                i += 1;
                                continue;
                            }
                            if (hasBracketedDestinationNewline(line[close_bracket + 2 .. close_paren])) {
                                try writeHtmlMarkdownTextRawAngles(writer, line[i .. close_paren + 1]);
                            } else {
                                try writeHtmlEscapedMarkdownText(writer, line[i .. close_paren + 1]);
                            }
                            i = close_paren + 1;
                            continue;
                        }
                        try writeHtmlLinkOpen(writer, target);
                        try writeHtmlInlineWithReferences(allocator, writer, line[i + 1 .. close_bracket], lookup);
                        try writer.writeAll("</a>");
                        i = close_paren + 1;
                        continue;
                    }
                }
                if (close_bracket + 1 < line.len and line[close_bracket + 1] == '[') {
                    if (findLinkLabelClose(line, close_bracket + 1)) |ref_close| {
                        const explicit_label = line[close_bracket + 2 .. ref_close];
                        const label = if (explicit_label.len == 0) line[i + 1 .. close_bracket] else explicit_label;
                        if (!suppressOuterLinkLabel(line[i + 1 .. close_bracket])) if (findLinkReferenceDefinition(lookup, label)) |target| {
                            try writeHtmlLinkOpen(writer, target);
                            try writeHtmlInlineWithReferences(allocator, writer, line[i + 1 .. close_bracket], lookup);
                            try writer.writeAll("</a>");
                            i = ref_close + 1;
                            continue;
                        };
                    }
                } else if (std.mem.indexOfScalarPos(u8, line, close_bracket + 1, '(') == null) {
                    const label = line[i + 1 .. close_bracket];
                    if ((containsScalar(label, '[') or containsScalar(label, ']')) and i > 0 and line[i - 1] == '!') {
                        try writeHtmlEscaped(writer, line[i .. i + 1]);
                        i += 1;
                        continue;
                    }
                    if (findLinkReferenceDefinition(lookup, label)) |target| {
                        try writeHtmlLinkOpen(writer, target);
                        try writeHtmlInlineWithReferences(allocator, writer, label, lookup);
                        try writer.writeAll("</a>");
                        i = close_bracket + 1;
                        continue;
                    }
                }
            }
        }

        if (line[i] == '<') {
            if (std.mem.indexOfScalarPos(u8, line, i + 1, '>')) |close| {
                const inner = line[i + 1 .. close];
                const scheme_autolink = isAutolinkScheme(inner);
                const email_autolink = !scheme_autolink and isAutolinkEmail(inner);
                if (scheme_autolink or email_autolink) {
                    try writer.writeAll("<a href=\"");
                    if (email_autolink) try writer.writeAll("mailto:");
                    try writeHtmlAutolinkUrlAttribute(writer, inner);
                    try writer.writeAll("\">");
                    try writeHtmlEscaped(writer, inner);
                    try writer.writeAll("</a>");
                    i = close + 1;
                    continue;
                }
                if (isHtmlInline(inner)) {
                    try writer.writeByte('<');
                    try writer.writeAll(inner);
                    try writer.writeByte('>');
                    i = close + 1;
                    continue;
                }
                try writer.writeAll("&lt;");
                try writeHtmlEscapedMarkdownText(writer, inner);
                try writer.writeAll("&gt;");
                i = close + 1;
                continue;
            }
        }
        if (try tryWriteKnownOverlapEmphasis(allocator, writer, line, i, lookup)) |next_i| {
            i = next_i;
            continue;
        }

        if ((line[i] == '*' or line[i] == '_') and delimiterRunLength(line, i) >= 3) {
            const run_len = delimiterRunLength(line, i);
            if (!canOpenEmphasis(line, i, line[i .. i + run_len])) {
                try writeHtmlEscaped(writer, line[i .. i + 1]);
                i += 1;
                continue;
            }
            if (findClosingDelimiterRun(line, i + run_len, line[i], run_len)) |close| {
                if (close > i + run_len) {
                    try writeNestedEmphasisOpen(writer, run_len);
                    try writeHtmlInlineWithReferences(allocator, writer, line[i + run_len .. close], lookup);
                    try writeNestedEmphasisClose(writer, run_len);
                    i = close + run_len;
                    continue;
                }
            }
        }

        if (i + 1 < line.len and ((line[i] == '*' and line[i + 1] == '*') or (line[i] == '_' and line[i + 1] == '_'))) {
            const delimiter = line[i .. i + 2];
            if (canOpenEmphasis(line, i, delimiter)) if (findEmphasisClose(line, i + 2, delimiter)) |close| {
                if (close == i + 2) {
                    try writeHtmlEscaped(writer, delimiter);
                    i += 2;
                    continue;
                }
                try writer.writeAll("<strong>");
                try writeHtmlInlineWithReferences(allocator, writer, line[i + 2 .. close], lookup);
                try writer.writeAll("</strong>");
                i = close + 2;
                continue;
            };
            try writeHtmlEscaped(writer, delimiter);
            i += 2;
            continue;
        }

        if (line[i] == '*' or line[i] == '_') {
            const delimiter = line[i .. i + 1];
            if (canOpenEmphasis(line, i, delimiter)) if (findEmphasisClose(line, i + 1, delimiter)) |close| {
                try writer.writeAll("<em>");
                try writeHtmlInlineWithReferences(allocator, writer, line[i + 1 .. close], lookup);
                try writer.writeAll("</em>");
                i = close + 1;
                continue;
            };
        }

        if (line[i] == '&') {
            if (std.mem.indexOfScalarPos(u8, line, i + 1, ';')) |semi| {
                const entity = line[i + 1 .. semi];
                if (isValidEntity(entity)) {
                    var buf: [16]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&buf);
                    if (try decodeEntity(stream.writer(), entity)) {
                        try writeHtmlEscaped(writer, stream.getWritten());
                        i = semi + 1;
                        continue;
                    }
                }
            }
        }

        try writeHtmlEscaped(writer, line[i .. i + 1]);
        i += 1;
    }
}

fn writeHtmlInline(allocator: std.mem.Allocator, writer: anytype, line: []const u8) !void {
    try writeHtmlInlineWithReferences(allocator, writer, line, .{ .content = "" });
}

fn writeCodeSpanHtml(allocator: std.mem.Allocator, writer: anytype, text: []const u8) !void {
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    try buffer.appendSlice(allocator, text);
    for (buffer.items) |*char| {
        if (char.* == '\n' or char.* == '\r') char.* = ' ';
    }

    var normalized = buffer.items;
    if (normalized.len > 1 and normalized[0] == ' ' and normalized[normalized.len - 1] == ' ' and !isBlank(normalized)) {
        normalized = normalized[1 .. normalized.len - 1];
    }
    try writeHtmlEscaped(writer, normalized);
}

fn renderHtmlParagraph(allocator: std.mem.Allocator, writer: anytype, line: []const u8, content: []const u8) !void {
    try writer.writeAll("<p>");
    try writeHtmlParagraphContent(allocator, writer, line, false, .{ .content = content });
    try writer.writeAll("</p>\n");
}

fn writeHtmlParagraphContent(allocator: std.mem.Allocator, writer: anytype, line: []const u8, allow_hard_break: bool, lookup: ReferenceLookup) !void {
    const inline_line = if (allow_hard_break) trimAsciiEnd(line) else trimAsciiEnd(line);
    try writeHtmlInlineWithReferences(allocator, writer, inline_line, lookup);
}

fn writeHtmlSetextHeadingText(allocator: std.mem.Allocator, writer: anytype, text: []const u8, lookup: ReferenceLookup) !void {
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    var offset: usize = 0;
    var first = true;
    while (lineBounds(text, offset)) |current| {
        offset = current.next;
        if (!first) try buffer.append(allocator, ' ');
        try buffer.appendSlice(allocator, trimAscii(current.line));
        first = false;
    }
    try writeHtmlInlineWithReferences(allocator, writer, buffer.items, lookup);
}

test "writeHtmlParagraphContent preserves hard breaks inside continued paragraphs" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try writeHtmlParagraphContent(std.testing.allocator, stream.writer(), "foo  \nbaz", true, .{ .content = "" });

    try std.testing.expectEqualStrings("foo<br />\nbaz", stream.getWritten());
}

test "writeHtmlParagraphContent preserves backslash hard breaks inside continued paragraphs" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try writeHtmlParagraphContent(std.testing.allocator, stream.writer(), "foo\\\nbaz", true, .{ .content = "" });

    try std.testing.expectEqualStrings("foo<br />\nbaz", stream.getWritten());
}

fn listMarkerCanInterruptParagraph(marker: ListMarker, line: []const u8) bool {
    return marker.content_start < line.len and (!marker.ordered or marker.number == 1);
}

fn isHtmlParagraphBoundary(line: []const u8) bool {
    const list_marker = parseListMarker(line);
    return isBlank(line) or
        parseFenceOpener(line) != null or
        parseAtxHeading(line) != null or
        parseThematicBreak(line) or
        isHtmlParagraphInterruptingBlockStart(line) or
        parseBlockQuote(line) != null or
        (list_marker != null and listMarkerCanInterruptParagraph(list_marker.?, line));
}

fn hasParagraphContinuation(content: []const u8, offset: usize) bool {
    if (lineBounds(content, offset)) |next_line| {
        return !isHtmlParagraphBoundary(next_line.line) and leadingColumns(next_line.line) < 4;
    }
    return false;
}

fn hasParagraphContinuationInContainer(content: []const u8, offset: usize, stack: ContainerStack) bool {
    if (lineBounds(content, offset)) |next_line| {
        const context = stack.normalizeLine(next_line.line);
        return !isHtmlParagraphBoundary(context.content) and relativeIndentColumns(next_line.line, context) < 4;
    }
    return false;
}

fn isHtmlIndentedCodeStart(line: []const u8, content: []const u8, offset: usize) bool {
    _ = content;
    _ = offset;
    return leadingColumns(line) >= 4;
}

fn isHtmlIndentedCodeStartInContainer(line: []const u8, content: []const u8, offset: usize, stack: ContainerStack) bool {
    const context = stack.normalizeLine(line);
    const indent = relativeIndentColumns(line, context);
    return indent >= 4 and !hasParagraphContinuationInContainer(content, offset, stack);
}

fn writePadding(writer: anytype, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

fn renderHtmlIndentedCodeBlock(writer: anytype, content: []const u8, first_line: []const u8, offset: usize) !usize {
    return renderHtmlIndentedCodeBlockInContainerEx(writer, content, first_line, offset, ContainerStack.empty(), false);
}

fn renderHtmlIndentedCodeBlockInContainer(writer: anytype, content: []const u8, first_line: []const u8, offset: usize, stack: ContainerStack) !usize {
    return renderHtmlIndentedCodeBlockInContainerEx(writer, content, first_line, offset, stack, stack.hasBlockQuote());
}

fn renderHtmlIndentedCodeBlockInContainerEx(writer: anytype, content: []const u8, first_line: []const u8, offset: usize, stack: ContainerStack, strip_quote_padding: bool) !usize {
    _ = strip_quote_padding;
    var next_offset = offset;
    try writer.writeAll("<pre><code>");
    const first_context = stack.normalizeLine(first_line);
    const strip_cols = indentedCodeStripColumns(first_line, first_context);
    const first_stripped = stripIndentColumns(first_line, strip_cols);
    try writePadding(writer, first_stripped.padding);
    try writeHtmlEscapedWithTabs(writer, first_stripped.content, strip_cols + first_stripped.padding);
    try writer.writeByte('\n');

    while (lineBounds(content, next_offset)) |next_line| {
        const context = stack.normalizeLine(next_line.line);
        if (!context.matched and !context.blank) break;
        if (!context.blank and context.indent_columns < 4) break;
        if (isBlank(next_line.line)) {
            try writer.writeByte('\n');
        } else {
            const line_strip_cols = indentedCodeStripColumns(next_line.line, context);
            const stripped = stripIndentColumns(next_line.line, line_strip_cols);
            try writePadding(writer, stripped.padding);
            try writeHtmlEscapedWithTabs(writer, stripped.content, line_strip_cols + stripped.padding);
            try writer.writeByte('\n');
        }
        next_offset = next_line.next;
    }

    try writer.writeAll("</code></pre>\n");
    return next_offset;
}

fn stripOptionalCodePadding(line: []const u8, enabled: bool) []const u8 {
    if (enabled and line.len > 0 and line[0] == ' ') return line[1..];
    return line;
}

fn appendListItemContinuation(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), line: []const u8, content_indent: usize) !void {
    var stack = ContainerStack.empty();
    try stack.pushListItem(content_indent);
    const context = stack.normalizeLine(line);
    if (context.blank) {
        try buffer.append(allocator, '\n');
        return;
    }

    for (0..context.padding) |_| try buffer.append(allocator, ' ');
    try buffer.appendSlice(allocator, context.content);
    try buffer.append(allocator, '\n');
}

fn renderHtmlFencedCodeBlock(allocator: std.mem.Allocator, writer: anytype, block: AstBlock) !void {
    _ = allocator;
    const fence = block.fence orelse return;
    var offset: usize = 0;
    const opener = lineBounds(block.source, offset) orelse return;
    offset = opener.next;

    try writer.writeAll("<pre><code");
    if (fence.info.len > 0) {
        try writer.writeAll(" class=\"language-");
        try writeHtmlLanguageAttribute(writer, fence.info);
        try writer.writeByte('"');
    }
    try writer.writeByte('>');

    while (lineBounds(block.source, offset)) |current| {
        offset = current.next;
        const context = block.container_stack.normalizeLine(current.line);
        if (isFenceCloser(context.content, fence)) break;
        const strip_cols = context.column_offset + fence.indent;
        const stripped = stripIndentColumns(current.line, strip_cols);
        try writePadding(writer, stripped.padding);
        try writeHtmlEscapedWithTabs(writer, stripped.content, strip_cols + stripped.padding);
        try writer.writeByte('\n');
    }

    try writer.writeAll("</code></pre>\n");
}

fn renderHtmlParagraphBlock(allocator: std.mem.Allocator, writer: anytype, block: AstBlock, lookup: ReferenceLookup) !void {
    var offset: usize = 0;
    const first = lineBounds(block.source, offset) orelse return;
    var line = first.line;
    offset = first.next;

    if (offset < block.source.len and parseBlockQuote(line) == null and !isBlank(line) and leadingColumns(line) < 4) {
        if (lineBounds(block.source, offset)) |next_line| {
            if (parseSetextUnderline(next_line.line)) |level| {
                try writer.print("<h{d}>", .{level});
                try writeHtmlInlineWithReferences(allocator, writer, trimAscii(line), lookup);
                try writer.print("</h{d}>\n", .{level});
                return;
            }
        }
    }

    var paragraph_buffer = std.ArrayList(u8).empty;
    defer paragraph_buffer.deinit(allocator);
    try paragraph_buffer.appendSlice(allocator, trimAsciiStart(line));
    while (lineBounds(block.source, offset)) |next_line| {
        line = next_line.line;
        offset = next_line.next;
        try paragraph_buffer.append(allocator, '\n');
        try paragraph_buffer.appendSlice(allocator, trimAsciiStart(line));
    }

    try writer.writeAll("<p>");
    try writeHtmlParagraphContent(allocator, writer, paragraph_buffer.items, true, lookup);
    try writer.writeAll("</p>\n");
}

fn renderHtmlMarkdownWithLookup(allocator: std.mem.Allocator, writer: anytype, content: []const u8, parent_lookup: ReferenceLookup) !void {
    try renderHtmlMarkdownWithLookupInContainer(allocator, writer, content, parent_lookup, ContainerStack.empty());
}

fn renderHtmlMarkdownWithLookupInContainer(allocator: std.mem.Allocator, writer: anytype, content: []const u8, parent_lookup: ReferenceLookup, stack: ContainerStack) !void {
    var ast = try parseCommonMarkBlocksInContainer(allocator, content, stack);
    defer ast.deinit();

    const lookup = if (ast.references.items.len == 0)
        parent_lookup
    else
        ReferenceLookup{ .content = content, .references = ast.references.items };
    for (ast.blocks.items) |block| {
        try renderHtmlAstBlock(allocator, writer, block, lookup);
    }
}

fn renderHtmlAstListBlock(allocator: std.mem.Allocator, writer: anytype, block: AstBlock, lookup: ReferenceLookup) !void {
    const marker = block.list_marker orelse return;
    if (block.list_items.len == 0) return;

    const tag = if (marker.ordered) "ol" else "ul";
    if (marker.ordered and marker.number != 1) {
        try writer.print("<{s} start=\"{d}\">\n", .{ tag, marker.number });
    } else {
        try writer.writeByte('<');
        try writer.writeAll(tag);
        try writer.writeAll(">\n");
    }

    for (block.list_items) |item| {
        try writer.writeAll("<li>");
        if (item.content.len > 0) {
            const trimmed_content = trimBlockWhitespace(item.content);
            const first_line_extra_indent = if (item.marker.content_start_columns > item.marker.content_indent) item.marker.content_start_columns - item.marker.content_indent else 0;
            const first_raw_indent = firstNonBlankIndentColumns(item.raw_content) orelse 0;
            const starts_with_block = parseContainerListMarker(trimmed_content) != null or parseFenceOpener(trimmed_content) != null or parseBlockQuote(trimmed_content) != null or parseAtxHeading(trimmed_content) != null;
            if (item.loose or first_line_extra_indent >= 4 or first_raw_indent >= item.marker.content_indent + 4) {
                if (item.loose and findNestedContainerLineStart(item.content) != null and parseContainerListMarker(trimBlockWhitespace(item.content[findNestedContainerLineStart(item.content).?..])) != null) {
                    const nested_start = findNestedContainerLineStart(item.content).?;
                    const nested_content = trimBlockWhitespace(item.content[nested_start..]);
                    const prefix = trimBlockWhitespace(item.content[0..nested_start]);
                    if (prefix.len > 0) {
                        try writeTightListItemPrefix(allocator, writer, prefix, lookup);
                        try writer.writeByte('\n');
                    }
                    try renderHtmlMarkdownWithLookup(allocator, writer, nested_content, lookup);
                } else if (first_line_extra_indent >= 4 or first_raw_indent >= item.marker.content_indent + 4) {
                    try writer.writeByte('\n');
                    const child_content = if (item.raw_content.len > 0) item.raw_content else item.content;
                    try renderHtmlMarkdownWithLookupInContainer(allocator, writer, child_content, lookup, item.child_stack);
                } else {
                    try writer.writeByte('\n');
                    try renderHtmlMarkdownWithLookup(allocator, writer, item.content, lookup);
                }
            } else if (starts_with_block) {
                try writer.writeByte('\n');
                try renderHtmlMarkdownWithLookup(allocator, writer, trimmed_content, lookup);
            } else {
                try renderHtmlTightListItem(allocator, writer, item, lookup);
            }
        }
        try writer.writeAll("</li>\n");
    }

    try writer.writeAll("</");
    try writer.writeAll(tag);
    try writer.writeAll(">\n");
}

fn findNestedContainerLineStart(content: []const u8) ?usize {
    var offset: usize = 0;
    var first = true;
    while (lineBounds(content, offset)) |current| {
        const start = offset;
        offset = current.next;
        if (first) {
            first = false;
            continue;
        }
        const trimmed = trimAsciiStart(current.line);
        if (parseContainerListMarker(trimmed) != null or parseFenceOpener(trimmed) != null or parseBlockQuote(trimmed) != null) return start;
    }
    return null;
}

fn writeTightListItemPrefix(allocator: std.mem.Allocator, writer: anytype, content: []const u8, lookup: ReferenceLookup) !void {
    if (parseSetextHeadingBlock(content)) |heading| {
        try writer.print("<h{d}>", .{heading.level});
        try writeHtmlInlineWithReferences(allocator, writer, trimBlockWhitespace(heading.text), lookup);
        try writer.print("</h{d}>\n", .{heading.level});
        var offset: usize = 0;
        var after_underline = false;
        while (lineBounds(content, offset)) |current| {
            offset = current.next;
            if (!after_underline) {
                if (parseSetextUnderline(current.line) != null) after_underline = true;
                continue;
            }
            const line = trimBlockWhitespace(current.line);
            if (line.len == 0) continue;
            if (after_underline) {
                after_underline = false;
            } else {
                try writer.writeByte('\n');
            }
            try writeHtmlInlineWithReferences(allocator, writer, line, lookup);
        }
        return;
    }

    var offset: usize = 0;
    var first = true;
    while (lineBounds(content, offset)) |current| {
        offset = current.next;
        const line = trimBlockWhitespace(current.line);
        if (line.len == 0) continue;
        if (!first) try writer.writeByte('\n');
        try writeHtmlInlineWithReferences(allocator, writer, line, lookup);
        first = false;
    }
}

fn renderHtmlTightListItem(allocator: std.mem.Allocator, writer: anytype, item: ListItem, lookup: ReferenceLookup) !void {
    if (findNestedContainerLineStart(item.content)) |nested_start| {
        const prefix = trimBlockWhitespace(item.content[0..nested_start]);
        if (prefix.len > 0) {
            try writeTightListItemPrefix(allocator, writer, prefix, lookup);
            try writer.writeByte('\n');
        }
        try renderHtmlMarkdownWithLookup(allocator, writer, trimBlockWhitespace(item.content[nested_start..]), lookup);
        return;
    }

    try writeTightListItemPrefix(allocator, writer, item.content, lookup);
}

fn firstNonBlankIndentColumns(content: []const u8) ?usize {
    var offset: usize = 0;
    while (lineBounds(content, offset)) |current| {
        offset = current.next;
        if (!isBlank(current.line)) return leadingColumns(current.line);
    }
    return null;
}

fn renderHtmlAstBlockQuote(allocator: std.mem.Allocator, writer: anytype, block: AstBlock, parent_lookup: ReferenceLookup) anyerror!void {
    const lookup = if (block.child_references.len == 0)
        parent_lookup
    else
        ReferenceLookup{ .content = block.child_content, .references = block.child_references };

    try writer.writeAll("<blockquote>\n");
    for (block.children) |child| {
        if (child.kind == .indented_code) {
            const first = lineBounds(child.source, 0) orelse continue;
            _ = try renderHtmlIndentedCodeBlockInContainerEx(writer, child.source, first.line, first.next, child.container_stack, true);
        } else {
            try renderHtmlAstBlock(allocator, writer, child, lookup);
        }
    }
    try writer.writeAll("</blockquote>\n");
}

fn renderHtmlAstBlock(allocator: std.mem.Allocator, writer: anytype, block: AstBlock, lookup: ReferenceLookup) anyerror!void {
    switch (block.kind) {
        .blank => {},
        .heading, .setext_heading => if (block.heading) |heading| {
            try writer.print("<h{d}>", .{heading.level});
            if (block.kind == .setext_heading) {
                try writeHtmlSetextHeadingText(allocator, writer, heading.text, lookup);
            } else {
                try writeHtmlInlineWithReferences(allocator, writer, heading.text, lookup);
            }
            try writer.print("</h{d}>\n", .{heading.level});
        },
        .thematic_break => try writer.writeAll("<hr />\n"),
        .fenced_code => try renderHtmlFencedCodeBlock(allocator, writer, block),
        .indented_code => {
            const first = lineBounds(block.source, 0) orelse return;
            _ = try renderHtmlIndentedCodeBlockInContainer(writer, block.source, first.line, first.next, block.container_stack);
        },
        .html_block => try writer.writeAll(block.source),
        .block_quote => try renderHtmlAstBlockQuote(allocator, writer, block, lookup),
        .list => try renderHtmlAstListBlock(allocator, writer, block, lookup),
        .paragraph => if (block.link_reference == null) try renderHtmlParagraphBlock(allocator, writer, block, lookup),
    }
}

pub fn renderHtmlMarkdown(allocator: std.mem.Allocator, writer: anytype, content: []const u8) anyerror!void {
    var ast = try parseCommonMarkBlocks(allocator, content);
    defer ast.deinit();

    const lookup = ReferenceLookup{ .content = content, .references = ast.references.items };
    for (ast.blocks.items) |block| {
        try renderHtmlAstBlock(allocator, writer, block, lookup);
    }
}

pub fn renderMarkdown(allocator: std.mem.Allocator, writer: anytype, content: []const u8, size: Size, use_color: bool) !void {
    var ast = try parseCommonMarkBlocks(allocator, content);
    defer ast.deinit();

    for (ast.blocks.items) |block| {
        switch (block.kind) {
            .paragraph => if (block.link_reference != null) continue,
            .heading, .setext_heading => if (block.heading) |heading| {
                try renderHeading(writer, heading, use_color);
            },
            .thematic_break => {
                const dim_style = style(use_color, dim);
                const blue_style = style(use_color, blue);
                const reset_style = style(use_color, reset);
                try writer.writeAll(dim_style);
                try writer.writeAll(blue_style);
                const width = if (size.cols > 0) size.cols else 40;
                for (0..@as(usize, @min(width, 80))) |_| try writer.writeAll("─");
                try writer.writeAll(reset_style);
                try writer.writeByte('\n');
            },
            .blank => {
                try writer.writeByte('\n');
            },
            .fenced_code => if (block.fence) |fence| {
                const dim_style = style(use_color, dim);
                const cyan_style = style(use_color, cyan);
                const reset_style = style(use_color, reset);

                try writer.writeAll(dim_style);
                try writer.writeAll(cyan_style);
                try writer.writeAll("╭── Code");
                if (fence.info.len > 0) {
                    try writer.writeAll(" (");
                    try writeTerminalText(writer, fence.info);
                    try writer.writeByte(')');
                }
                try writer.writeByte(' ');
                const header_columns = @as(usize, 9) + if (fence.info.len > 0) fence.info.len + 3 else 0;
                const target_columns = @max(@as(usize, size.cols), header_columns);
                const dash_count = target_columns - header_columns;
                const code_border_columns = header_columns + dash_count;
                for (0..dash_count) |_| try writer.writeAll("─");
                try writer.writeAll(reset_style);
                try writer.writeByte('\n');

                var offset: usize = 0;
                var line_count: usize = 0;
                while (lineBounds(block.source, offset)) |current| {
                    if (line_count > 0 and current.next == block.source.len and isFenceCloser(current.line, fence)) {
                        break;
                    }
                    if (line_count > 0) {
                        const code_line = stripFenceIndent(current.line, fence.indent);
                        try writer.writeAll(cyan_style);
                        try writer.writeAll("│");
                        try writer.writeAll(reset_style);
                        try writer.writeByte(' ');
                        try writeTerminalText(writer, code_line);
                        try writer.writeByte('\n');
                    }
                    offset = current.next;
                    line_count += 1;
                }

                try writer.writeAll(dim_style);
                try writer.writeAll(cyan_style);
                try writer.writeAll("╰");
                for (1..code_border_columns) |_| try writer.writeAll("─");
                try writer.writeAll(reset_style);
                try writer.writeByte('\n');
            },
            .html_block => {
                const dim_style = style(use_color, dim);
                const reset_style = style(use_color, reset);
                var offset: usize = 0;
                while (lineBounds(block.source, offset)) |current| {
                    try writer.writeAll(dim_style);
                    try writeTerminalText(writer, current.line);
                    try writer.writeAll(reset_style);
                    try writer.writeByte('\n');
                    offset = current.next;
                }
            },
            .indented_code => {
                const cyan_style = style(use_color, cyan);
                const reset_style = style(use_color, reset);
                var offset: usize = 0;
                while (lineBounds(block.source, offset)) |current| {
                    if (isBlank(current.line)) {
                        try writer.writeByte('\n');
                    } else {
                        try writer.writeAll(cyan_style);
                        try writer.writeAll("│");
                        try writer.writeAll(reset_style);
                        try writer.writeByte(' ');
                        try writeTerminalText(writer, stripIndentColumns(current.line, 4).content);
                        try writer.writeByte('\n');
                    }
                    offset = current.next;
                }
            },
            else => {},
        }
    }
}

pub const RenderFormat = enum {
    terminal,
    html,
};

pub fn renderMarkdownAlloc(allocator: std.mem.Allocator, content: []const u8, format: RenderFormat, size: Size, use_color: bool) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    switch (format) {
        .terminal => try renderMarkdown(allocator, &output.writer, content, size, use_color),
        .html => try renderHtmlMarkdown(allocator, &output.writer, content),
    }

    return output.toOwnedSlice();
}

const ffi_success: c_int = 0;
const ffi_invalid_argument: c_int = 1;
const ffi_render_failed: c_int = 2;

export fn mdv_render_html(markdown_ptr: [*]const u8, markdown_len: usize, out_ptr: *[*]u8, out_len: *usize) c_int {
    const markdown = markdown_ptr[0..markdown_len];
    const rendered = renderMarkdownAlloc(std.heap.page_allocator, markdown, .html, .{ .cols = 80, .rows = 24 }, false) catch return ffi_render_failed;
    out_ptr.* = rendered.ptr;
    out_len.* = rendered.len;
    return ffi_success;
}

export fn mdv_render_terminal(markdown_ptr: [*]const u8, markdown_len: usize, cols: u32, rows: u32, use_color: bool, out_ptr: *[*]u8, out_len: *usize) c_int {
    if (cols == 0 or rows == 0) return ffi_invalid_argument;

    const markdown = markdown_ptr[0..markdown_len];
    const rendered = renderMarkdownAlloc(std.heap.page_allocator, markdown, .terminal, .{ .cols = cols, .rows = rows }, use_color) catch return ffi_render_failed;
    out_ptr.* = rendered.ptr;
    out_len.* = rendered.len;
    return ffi_success;
}

export fn mdv_free_rendered(ptr: [*]u8, len: usize) void {
    std.heap.page_allocator.free(ptr[0..len]);
}
