//! The text namespace provides ANSI-safe terminal text transformations.

const std = @import("std");
const ansi = @import("ansi.zig");
const escape = @import("escape.zig");
const term = @import("term.zig");

/// The stripAnsiAlloc function returns a copy of `text` without recognized ANSI control sequences.
pub fn stripAnsiAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var index: usize = 0;
    while (index < text.len) {
        const sequence_len = ansi.sequenceLen(text[index..]);
        if (sequence_len != 0) {
            index += sequence_len;
            continue;
        }
        const unit = term.displayUnitAt(text, index);
        try out.writer.writeAll(text[index .. index + unit.len]);
        index += unit.len;
    }
    return out.toOwnedSlice();
}

/// The cutAnsiAlloc function returns at most `cells` visible terminal cells from the first line of `text`.
pub fn cutAnsiAlloc(allocator: std.mem.Allocator, text: []const u8, cells: usize) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var index: usize = 0;
    var used: usize = 0;
    var wrote_sequence = false;
    var cut = false;
    while (index < text.len) {
        const sequence_len = ansi.sequenceLen(text[index..]);
        if (sequence_len != 0) {
            try out.writer.writeAll(text[index .. index + sequence_len]);
            wrote_sequence = true;
            index += sequence_len;
            continue;
        }
        const unit = term.displayUnitAt(text, index);
        if (text[index] == '\n' or used + unit.display_width > cells) {
            cut = true;
            break;
        }
        try out.writer.writeAll(text[index .. index + unit.len]);
        used += unit.display_width;
        index += unit.len;
    }
    if (cut and wrote_sequence) try out.writer.writeAll(escape.reset);
    return out.toOwnedSlice();
}

/// The truncateAnsiAlloc function cuts text to `cells` and appends `ellipsis` when content was omitted.
pub fn truncateAnsiAlloc(allocator: std.mem.Allocator, text: []const u8, cells: usize, ellipsis: []const u8) ![]u8 {
    if (term.ansiDisplayWidth(text) <= cells and std.mem.indexOfScalar(u8, text, '\n') == null) return allocator.dupe(u8, text);
    const ellipsis_width = term.utf8DisplayWidth(ellipsis);
    if (ellipsis_width >= cells) return cutAnsiAlloc(allocator, ellipsis, cells);
    const prefix = try cutAnsiAlloc(allocator, text, cells - ellipsis_width);
    defer allocator.free(prefix);
    return std.mem.concat(allocator, u8, &.{ prefix, ellipsis });
}

test "stripAnsiAlloc removes SGR and OSC sequences" {
    const stripped = try stripAnsiAlloc(std.testing.allocator, "\x1b[31mred\x1b[0m \x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\");
    defer std.testing.allocator.free(stripped);
    try std.testing.expectEqualStrings("red link", stripped);
}

test "cutAnsiAlloc cuts by cell width" {
    const cut = try cutAnsiAlloc(std.testing.allocator, "\x1b[31m你好x\x1b[0m", 4);
    defer std.testing.allocator.free(cut);
    try std.testing.expectEqualStrings("\x1b[31m你好\x1b[0m", cut);
}

test "truncateAnsiAlloc appends an ellipsis" {
    const truncated = try truncateAnsiAlloc(std.testing.allocator, "abcdef", 4, "…");
    defer std.testing.allocator.free(truncated);
    try std.testing.expectEqualStrings("abc…", truncated);
}
