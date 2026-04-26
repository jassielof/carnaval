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
pub const list = @import("components/list.zig");
pub const ListStyle = list.ListStyle;
pub const ListOptions = list.ListOptions;
pub const ListItem = list.ListItem;
pub const renderList = list.renderList;
pub const renderListItems = list.renderListItems;
pub const renderListAlloc = list.renderListAlloc;
pub const renderListItemsAlloc = list.renderListItemsAlloc;
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
pub const ansiDisplayWidth = term.ansiDisplayWidth;

comptime {
    _ = escape;
    _ = profile;
    _ = color;
    _ = Style;
    _ = term;
    _ = table;
    _ = list;
}

test "public API basic render" {
    const allocator = std.testing.allocator;
    const s = Style.init().fg(.{ .true_color = .{ .r = 255, .g = 120, .b = 0 } }).bolded();

    const out = try s.renderAllocWithProfile("carnaval", allocator, .true_color);
    defer allocator.free(out);

    try std.testing.expect(out.len > "carnaval".len);
}

test Style {
    const allocator = std.testing.allocator;
    const s = Style.init().fg(.{ .ansi16 = .green }).bolded();

    const out = try s.renderAllocWithProfile("ok", allocator, .ansi16);
    defer allocator.free(out);

    try std.testing.expectEqualStrings("\x1b[1m\x1b[32mok\x1b[0m", out);
}

test renderAsciiTable {
    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try renderAsciiTable(
        std.testing.allocator,
        &.{"Name"},
        &.{
            &.{"api"},
        },
        &writer,
    );

    try std.testing.expectEqualStrings(
        "+------+\n" ++
            "| Name |\n" ++
            "+------+\n" ++
            "| api  |\n" ++
            "+------+\n",
        writer.buffered(),
    );
}

test renderList {
    const out = try renderListAlloc(std.testing.allocator, &.{ "alpha", "beta" }, .{ .style = .dash });
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("- alpha\n- beta", out);
}
