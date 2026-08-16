//! ANSI-aware text measurement and composition primitives.

const std = @import("std");
const term = @import("term.zig");

/// Horizontal placement used by `joinVerticalAlloc`.
pub const HorizontalAlignment = enum { left, center, right };

/// Vertical placement used by `joinHorizontalAlloc`.
pub const VerticalAlignment = enum { top, center, bottom };

/// Terminal cell width of the widest line in `text`, ignoring ANSI escape sequences.
pub fn width(text: []const u8) usize {
    return term.ansiDisplayWidth(text);
}

/// Number of terminal lines in `text`. An empty string occupies one line.
pub fn height(text: []const u8) usize {
    return std.mem.count(u8, text, "\n") + 1;
}

/// Terminal cell dimensions of `text`, ignoring ANSI escape sequences for width.
pub fn size(text: []const u8) struct { width: usize, height: usize } {
    return .{ .width = width(text), .height = height(text) };
}

/// Horizontally combines multi-line blocks, aligning each block vertically.
///
/// Lines are padded with spaces according to their visible terminal width.
pub fn joinHorizontalAlloc(
    allocator: std.mem.Allocator,
    alignment: VerticalAlignment,
    blocks: []const []const u8,
) ![]u8 {
    if (blocks.len == 0) return allocator.dupe(u8, "");

    var block_heights = try allocator.alloc(usize, blocks.len);
    defer allocator.free(block_heights);
    var block_widths = try allocator.alloc(usize, blocks.len);
    defer allocator.free(block_widths);
    var max_height: usize = 0;
    for (blocks, 0..) |block, index| {
        const block_height = height(block);
        block_heights[index] = block_height;
        block_widths[index] = width(block);
        max_height = @max(max_height, block_height);
    }

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    for (0..max_height) |line_index| {
        for (blocks, block_heights, block_widths) |block, block_height, block_width| {
            const top_padding = verticalPadding(alignment, max_height - block_height);
            if (line_index < top_padding or line_index >= top_padding + block_height) {
                try writeSpaces(&out.writer, block_width);
                continue;
            }

            const line = lineAt(block, line_index - top_padding);
            try out.writer.writeAll(line);
            try writeSpaces(&out.writer, block_width - width(line));
        }
        if (line_index + 1 < max_height) try out.writer.writeByte('\n');
    }

    return out.toOwnedSlice();
}

/// Vertically combines blocks, aligning each line horizontally to the widest block.
pub fn joinVerticalAlloc(
    allocator: std.mem.Allocator,
    alignment: HorizontalAlignment,
    blocks: []const []const u8,
) ![]u8 {
    if (blocks.len == 0) return allocator.dupe(u8, "");

    var max_width: usize = 0;
    for (blocks) |block| max_width = @max(max_width, width(block));

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    for (blocks, 0..) |block, block_index| {
        var lines = std.mem.splitScalar(u8, block, '\n');
        while (lines.next()) |line| {
            const missing = max_width - width(line);
            const left = horizontalLeftPadding(alignment, missing);
            try writeSpaces(&out.writer, left);
            try out.writer.writeAll(line);
            try writeSpaces(&out.writer, missing - left);
            try out.writer.writeByte('\n');
        }
        _ = block_index;
    }

    const rendered = try out.toOwnedSlice();
    return allocator.realloc(rendered, rendered.len - 1);
}

fn lineAt(block: []const u8, wanted: usize) []const u8 {
    var lines = std.mem.splitScalar(u8, block, '\n');
    var index: usize = 0;
    while (lines.next()) |line| : (index += 1) {
        if (index == wanted) return line;
    }
    unreachable;
}

fn verticalPadding(alignment: VerticalAlignment, extra: usize) usize {
    return switch (alignment) {
        .top => 0,
        .center => extra / 2,
        .bottom => extra,
    };
}

fn horizontalLeftPadding(alignment: HorizontalAlignment, extra: usize) usize {
    return switch (alignment) {
        .left => 0,
        .center => extra / 2,
        .right => extra,
    };
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

test "size measures multiline ANSI text" {
    const dimensions = size("\x1b[31mred\x1b[0m\n你好");
    try std.testing.expectEqual(@as(usize, 4), dimensions.width);
    try std.testing.expectEqual(@as(usize, 2), dimensions.height);
}

test "joinHorizontalAlloc aligns blocks at the bottom" {
    const rendered = try joinHorizontalAlloc(std.testing.allocator, .bottom, &.{ "one\ntwo", "X" });
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("one \ntwoX", rendered);
}

test "joinHorizontalAlloc preserves blank columns for vertically absent blocks" {
    const rendered = try joinHorizontalAlloc(std.testing.allocator, .top, &.{ "X", "one\ntwo" });
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("Xone\n two", rendered);
}

test "joinVerticalAlloc centers ANSI-aware lines" {
    const rendered = try joinVerticalAlloc(std.testing.allocator, .center, &.{ "\x1b[31mred\x1b[0m", "x" });
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m\n x ", rendered);
}
