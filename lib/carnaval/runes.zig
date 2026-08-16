//! The runes namespace applies styles to selected UTF-8 codepoint indexes.

const std = @import("std");
const Style = @import("Style.zig");
const ColorProfile = @import("profile.zig").ColorProfile;

/// The styleRunesAlloc function styles selected codepoint indexes and leaves all other text plain.
pub fn styleRunesAlloc(allocator: std.mem.Allocator, input: []const u8, indexes: []const usize, style: Style, profile: ColorProfile) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var index: usize = 0;
    var codepoint_index: usize = 0;
    while (index < input.len) : (codepoint_index += 1) {
        const length = std.unicode.utf8ByteSequenceLength(input[index]) catch 1;
        const bytes = input[index .. index + length];
        var selected = false;
        for (indexes) |wanted| if (wanted == codepoint_index) {
            selected = true;
            break;
        };
        if (selected) try style.renderWithProfile(bytes, &out.writer, profile) else try out.writer.writeAll(bytes);
        index += length;
    }
    return out.toOwnedSlice();
}

test "styleRunesAlloc styles selected codepoints" {
    const output = try styleRunesAlloc(std.testing.allocator, "abc", &.{1}, Style.init().bolded(), .ansi16);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("a\x1b[1mb\x1b[0mc", output);
}
