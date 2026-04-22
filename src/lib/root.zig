const std = @import("std");

pub const color = @import("color.zig");
pub const Ansi16 = color.Ansi16;
pub const Rgb = color.Rgb;
pub const Color = color.Color;
pub const table = @import("components/table.zig");
pub const TableStyle = table.TableStyle;
pub const renderTable = table.renderTable;
pub const renderTableStyled = table.renderTableStyled;
pub const renderAsciiTable = table.renderAscii;
pub const renderAsciiTableStyled = table.renderAsciiStyled;
pub const escape = @import("escape.zig");
pub const profile = @import("profile.zig");
pub const ColorProfile = profile.ColorProfile;
pub const colorProfile = profile.colorProfile;
pub const colorProfileForHandle = profile.colorProfileForHandle;
pub const Style = @import("Style.zig");
pub const term = @import("term.zig");
pub const terminalWidth = term.terminalWidth;
pub const terminalWidthForHandle = term.terminalWidthForHandle;
pub const prepareWindowsConsoleIfNeeded = term.prepareWindowsConsoleIfNeeded;
pub const isWindowsConsoleHandle = term.isWindowsConsoleHandle;
pub const wrap = term.wrap;
pub const wrapAnsi = term.wrapAnsi;
pub const utf8DisplayWidth = term.utf8DisplayWidth;

comptime {
    _ = escape;
    _ = profile;
    _ = color;
    _ = Style;
    _ = term;
    _ = table;
}

test "public API basic render" {
    const allocator = std.testing.allocator;
    const s = Style.init().fg(.{ .true_color = .{ .r = 255, .g = 120, .b = 0 } }).bolded();

    const out = try s.renderAllocWithProfile("carnaval", allocator, .true_color);
    defer allocator.free(out);

    try std.testing.expect(out.len > "carnaval".len);
}
