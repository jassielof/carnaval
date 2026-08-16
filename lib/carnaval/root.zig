//! The carnaval package provides ANSI-aware terminal styling and layout primitives.

const std = @import("std");

pub const color = @import("color.zig");
pub const Ansi16 = color.Ansi16;
pub const Rgb = color.Rgb;
pub const Color = color.Color;
pub const blend = color.blend;
pub const lighten = color.lighten;
pub const darken = color.darken;
pub const complementary = color.complementary;
pub const blend1dAlloc = color.blend1dAlloc;
pub const blend2dAlloc = color.blend2dAlloc;
pub const Border = @import("Border.zig");
pub const Insets = @import("Insets.zig");
pub const list = @import("components/list.zig");
pub const ListStyle = list.ListStyle;
pub const ListOptions = list.ListOptions;
pub const ListItem = list.ListItem;
pub const renderList = list.renderList;
pub const renderListItems = list.renderListItems;
pub const renderListAlloc = list.renderListAlloc;
pub const renderListItemsAlloc = list.renderListItemsAlloc;
pub const table = @import("components/table.zig");
pub const TableStyle = table.TableStyle;
pub const TableOptions = table.TableOptions;
pub const renderTableWithOptions = table.renderTableWithOptions;
pub const renderTable = table.renderTable;
pub const renderTableStyled = table.renderTableStyled;
pub const renderTableAlloc = table.renderTableAlloc;
pub const renderTableStyledAlloc = table.renderTableStyledAlloc;
pub const renderAsciiTable = table.renderAscii;
pub const renderAsciiTableStyled = table.renderAsciiStyled;
pub const renderAsciiTableAlloc = table.renderAsciiAlloc;
pub const renderAsciiTableStyledAlloc = table.renderAsciiStyledAlloc;
pub const escape = @import("escape.zig");
pub const ansi = @import("ansi.zig");
pub const text = @import("text.zig");
pub const stripAnsiAlloc = text.stripAnsiAlloc;
pub const cutAnsiAlloc = text.cutAnsiAlloc;
pub const truncateAnsiAlloc = text.truncateAnsiAlloc;
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
pub const WrapOptions = term.WrapOptions;
pub const wrap = term.wrap;
pub const wrapWithOptions = term.wrapWithOptions;
pub const wrapAnsi = term.wrapAnsi;
pub const wrapAnsiWithOptions = term.wrapAnsiWithOptions;
pub const utf8DisplayWidth = term.utf8DisplayWidth;
pub const ansiDisplayWidth = term.ansiDisplayWidth;
pub const layout = @import("layout.zig");
pub const HorizontalAlignment = layout.HorizontalAlignment;
pub const VerticalAlignment = layout.VerticalAlignment;
pub const width = layout.width;
pub const height = layout.height;
pub const size = layout.size;
pub const joinHorizontalAlloc = layout.joinHorizontalAlloc;
pub const joinVerticalAlloc = layout.joinVerticalAlloc;
pub const place = @import("place.zig");
pub const placeAlloc = place.placeAlloc;
pub const placeHorizontalAlloc = place.placeHorizontalAlloc;
pub const placeVerticalAlloc = place.placeVerticalAlloc;
pub const ranges = @import("ranges.zig");
pub const Range = ranges.Range;
pub const styleRangesAlloc = ranges.styleRangesAlloc;
pub const tree = @import("components/tree.zig");
pub const TreeNode = tree.TreeNode;
pub const TreeOptions = tree.TreeOptions;
pub const renderTreeAlloc = tree.renderAlloc;
pub const Canvas = @import("canvas.zig").Canvas;
pub const whitespace = @import("whitespace.zig");
pub const fillWhitespaceAlloc = whitespace.fillAlloc;
pub const runes = @import("runes.zig");
pub const styleRunesAlloc = runes.styleRunesAlloc;

comptime {
    std.testing.refAllDecls(@This());
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

test "joinVerticalAlloc" {
    const out = try joinVerticalAlloc(std.testing.allocator, .center, &.{ "wide", "x" });
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("wide\n x  ", out);
}

test "renderTableAlloc" {
    const out = try renderTableAlloc(std.testing.allocator, &.{"Name"}, &.{&.{"Carnaval"}}, .ascii);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("+----------+\n| Name     |\n+----------+\n| Carnaval |\n+----------+\n", out);
}
