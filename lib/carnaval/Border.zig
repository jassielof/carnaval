//! The Border namespace defines the glyphs used to frame a rendered block.

const Border = @This();

/// The string written repeatedly across the top edge.
top: []const u8 = "",
/// The string written repeatedly across the right edge.
right: []const u8 = "",
/// The string written repeatedly across the bottom edge.
bottom: []const u8 = "",
/// The string written repeatedly across the left edge.
left: []const u8 = "",
/// The string written at the top-left corner.
top_left: []const u8 = "",
/// The string written at the top-right corner.
top_right: []const u8 = "",
/// The string written at the bottom-right corner.
bottom_right: []const u8 = "",
/// The string written at the bottom-left corner.
bottom_left: []const u8 = "",

/// The normal function returns a light box-drawing border.
pub fn normal() Border {
    return .{
        .top = "─",
        .right = "│",
        .bottom = "─",
        .left = "│",
        .top_left = "┌",
        .top_right = "┐",
        .bottom_right = "┘",
        .bottom_left = "└",
    };
}

/// The rounded function returns a light border with rounded corners.
pub fn rounded() Border {
    return .{
        .top = "─",
        .right = "│",
        .bottom = "─",
        .left = "│",
        .top_left = "╭",
        .top_right = "╮",
        .bottom_right = "╯",
        .bottom_left = "╰",
    };
}

/// The block function returns a solid block border.
pub fn block() Border {
    return .{
        .top = "█",
        .right = "█",
        .bottom = "█",
        .left = "█",
        .top_left = "█",
        .top_right = "█",
        .bottom_right = "█",
        .bottom_left = "█",
    };
}

/// The thick function returns a heavy box-drawing border.
pub fn thick() Border {
    return .{
        .top = "━",
        .right = "┃",
        .bottom = "━",
        .left = "┃",
        .top_left = "┏",
        .top_right = "┓",
        .bottom_right = "┛",
        .bottom_left = "┗",
    };
}

/// The double function returns a double-line box-drawing border.
pub fn double() Border {
    return .{
        .top = "═",
        .right = "║",
        .bottom = "═",
        .left = "║",
        .top_left = "╔",
        .top_right = "╗",
        .bottom_right = "╝",
        .bottom_left = "╚",
    };
}

/// The ascii function returns a seven-bit-safe border.
pub fn ascii() Border {
    return .{
        .top = "-",
        .right = "|",
        .bottom = "-",
        .left = "|",
        .top_left = "+",
        .top_right = "+",
        .bottom_right = "+",
        .bottom_left = "+",
    };
}

/// The markdown function returns the border convention used by Markdown tables.
pub fn markdown() Border {
    return .{
        .top = "-",
        .right = "|",
        .bottom = "-",
        .left = "|",
        .top_left = "|",
        .top_right = "|",
        .bottom_right = "|",
        .bottom_left = "|",
    };
}

/// The hidden function returns a space-filling border that preserves geometry.
pub fn hidden() Border {
    return .{
        .top = " ",
        .right = " ",
        .bottom = " ",
        .left = " ",
        .top_left = " ",
        .top_right = " ",
        .bottom_right = " ",
        .bottom_left = " ",
    };
}

test "Border presets expose expected corners" {
    try @import("std").testing.expectEqualStrings("┌", normal().top_left);
    try @import("std").testing.expectEqualStrings("╚", double().bottom_left);
    try @import("std").testing.expectEqualStrings("+", ascii().top_right);
}
