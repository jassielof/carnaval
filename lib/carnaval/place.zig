//! The place namespace positions ANSI-aware text inside a terminal-cell rectangle.

const std = @import("std");
const layout = @import("layout.zig");
const text_util = @import("text.zig");

/// The placeAlloc function positions `text` in a rectangle, filling unused cells with `fill`.
pub fn placeAlloc(allocator: std.mem.Allocator, width: usize, height: usize, horizontal: layout.HorizontalAlignment, vertical: layout.VerticalAlignment, text: []const u8, fill: u8) ![]u8 {
    const text_height = layout.height(text);
    const visible_height = @min(height, text_height);
    const top = switch (vertical) {
        .top => 0,
        .center => (height - visible_height) / 2,
        .bottom => height - visible_height,
    };
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    var line_index: usize = 0;
    while (line_index < height) : (line_index += 1) {
        if (line_index >= top and line_index < top + visible_height) {
            const line = nthLine(text, line_index - top);
            const line_width = @min(width, layout.width(line));
            const left = switch (horizontal) {
                .left => 0,
                .center => (width - line_width) / 2,
                .right => width - line_width,
            };
            try repeat(&writer.writer, fill, left);
            if (layout.width(line) > width) {
                const cut = try text_util.cutAnsiAlloc(allocator, line, width);
                defer allocator.free(cut);
                try writer.writer.writeAll(cut);
            } else try writer.writer.writeAll(line);
            try repeat(&writer.writer, fill, width - left - line_width);
        } else try repeat(&writer.writer, fill, width);
        if (line_index + 1 < height) try writer.writer.writeByte('\n');
    }
    return writer.toOwnedSlice();
}

/// The placeHorizontalAlloc function positions text horizontally in `width` cells.
pub fn placeHorizontalAlloc(allocator: std.mem.Allocator, width: usize, horizontal: layout.HorizontalAlignment, text: []const u8, fill: u8) ![]u8 {
    return placeAlloc(allocator, width, layout.height(text), horizontal, .top, text, fill);
}

/// The placeVerticalAlloc function positions text vertically in `height` lines.
pub fn placeVerticalAlloc(allocator: std.mem.Allocator, height: usize, vertical: layout.VerticalAlignment, text: []const u8, fill: u8) ![]u8 {
    return placeAlloc(allocator, layout.width(text), height, .left, vertical, text, fill);
}

fn nthLine(text: []const u8, wanted: usize) []const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var index: usize = 0;
    while (lines.next()) |line| : (index += 1) if (index == wanted) return line;
    return "";
}

fn repeat(writer: *std.Io.Writer, fill: u8, count: usize) !void {
    for (0..count) |_| try writer.writeByte(fill);
}

test "placeAlloc centers text" {
    const result = try placeAlloc(std.testing.allocator, 5, 3, .center, .center, "x", '.');
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(".....\n..x..\n.....", result);
}
