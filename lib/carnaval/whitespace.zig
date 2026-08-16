//! The whitespace namespace creates terminal-cell fill with optional ANSI styling.

const std = @import("std");
const Style = @import("Style.zig");
const ColorProfile = @import("profile.zig").ColorProfile;

/// The fillAlloc function returns `count` copies of `glyph`, optionally rendered with `style`.
pub fn fillAlloc(allocator: std.mem.Allocator, glyph: []const u8, count: usize, style: Style, profile: ColorProfile) ![]u8 {
    var raw = std.Io.Writer.Allocating.init(allocator);
    defer raw.deinit();
    for (0..count) |_| try raw.writer.writeAll(glyph);
    const text = try raw.toOwnedSlice();
    defer allocator.free(text);
    return style.renderAllocWithProfile(text, allocator, profile);
}

test "fillAlloc renders styled whitespace" {
    const result = try fillAlloc(std.testing.allocator, "·", 3, Style.init().bolded(), .ansi16);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\x1b[1m···\x1b[0m", result);
}
