//! The ranges namespace applies Carnaval styles to visible terminal-cell ranges.

const std = @import("std");
const ansi = @import("ansi.zig");
const term = @import("term.zig");
const Style = @import("Style.zig");
const ColorProfile = @import("profile.zig").ColorProfile;

/// The Range structure identifies a half-open visible-cell interval and its style.
pub const Range = struct { start: usize, end: usize, style: Style };

/// The styleRangesAlloc function applies non-overlapping cell ranges to ANSI-free text.
pub fn styleRangesAlloc(allocator: std.mem.Allocator, input: []const u8, ranges: []const Range, profile: ColorProfile) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var byte_index: usize = 0;
    var cells: usize = 0;
    while (byte_index < input.len) {
        const sequence_len = ansi.sequenceLen(input[byte_index..]);
        if (sequence_len != 0) return error.InputContainsAnsi;
        const unit = term.displayUnitAt(input, byte_index);
        const next = cells + unit.display_width;
        var selected: ?Style = null;
        for (ranges) |range| if (cells >= range.start and next <= range.end) {
            selected = range.style;
            break;
        };
        const bytes = input[byte_index .. byte_index + unit.len];
        if (selected) |style| try style.renderWithProfile(bytes, &out.writer, profile) else try out.writer.writeAll(bytes);
        byte_index += unit.len;
        cells = next;
    }
    return out.toOwnedSlice();
}

test "styleRangesAlloc applies a visible-cell range" {
    const rendered = try styleRangesAlloc(std.testing.allocator, "a好b", &.{.{ .start = 1, .end = 3, .style = Style.init().bolded() }}, .ansi16);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("a\x1b[1m好\x1b[0mb", rendered);
}
