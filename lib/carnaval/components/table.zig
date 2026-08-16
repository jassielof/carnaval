//! Tabular output: ASCII grid (portable), Markdown pipe tables (GFM), and Unicode light borders similar to Charmbracelet Lip Gloss `Border.Normal`.
//!
//! On Windows consoles, UTF-8 output is enabled automatically the first time Carnaval talks to the console (`terminalWidth*`, `colorProfile*`, or a Unicode table).

const std = @import("std");

const ColorProfile = @import("../profile.zig").ColorProfile;
const Style = @import("../Style.zig");
const term = @import("../term.zig");

/// Visual style for `renderTable` / `renderTableStyled`.
pub const TableStyle = enum {
    /// `+---+' grid; safe on legacy Windows code pages.
    ascii,
    /// GitHub-flavored Markdown: `| --- |` separator row, no outer frame.
    markdown,
    /// Lip Gloss–style light box drawing (`┌┬┐│─┼└┴┘`). UTF-8; Windows console is prepared automatically.
    unicode,
};

pub fn renderTable(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: *std.Io.Writer,
    style: TableStyle,
) !void {
    return renderTableStyled(allocator, headers, rows, writer, .none, style);
}

/// Renders a table. Header row uses bold when `color_profile` is not `.none`.
pub fn renderTableStyled(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: *std.Io.Writer,
    color_profile: ColorProfile,
    style: TableStyle,
) !void {
    if (headers.len == 0) return;

    for (rows) |row| {
        if (row.len != headers.len) return error.TableColumnCountMismatch;
    }

    if (style == .unicode) {
        term.prepareWindowsConsoleIfNeeded(std.Io.File.stdout().handle);
    }

    const widths = try computeWidths(headers, rows, allocator);
    defer allocator.free(widths);

    switch (style) {
        .ascii => try renderAsciiGrid(writer, headers, rows, widths, color_profile),
        .markdown => try renderMarkdown(writer, headers, rows, widths, color_profile),
        .unicode => try renderUnicodeGrid(writer, headers, rows, widths, color_profile),
    }
}

/// Like `renderTable`, but returns an owned buffer allocated with `allocator`.
pub fn renderTableAlloc(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    style: TableStyle,
) ![]u8 {
    return renderTableStyledAlloc(allocator, headers, rows, .none, style);
}

/// Like `renderTableStyled`, but returns an owned buffer allocated with `allocator`.
pub fn renderTableStyledAlloc(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    color_profile: ColorProfile,
    style: TableStyle,
) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try renderTableStyled(allocator, headers, rows, &writer.writer, color_profile, style);
    return writer.toOwnedSlice();
}

/// Renders an ASCII `+---+' table (styled header when color is enabled).
pub fn renderAscii(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: *std.Io.Writer,
) !void {
    return renderTable(allocator, headers, rows, writer, .ascii);
}

/// Like `renderAscii`, but returns an owned buffer allocated with `allocator`.
pub fn renderAsciiAlloc(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
) ![]u8 {
    return renderTableAlloc(allocator, headers, rows, .ascii);
}

/// Same as `renderAscii` with explicit color profile for the header row.
pub fn renderAsciiStyled(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: *std.Io.Writer,
    color_profile: ColorProfile,
) !void {
    return renderTableStyled(allocator, headers, rows, writer, color_profile, .ascii);
}

/// Like `renderAsciiStyled`, but returns an owned buffer allocated with `allocator`.
pub fn renderAsciiStyledAlloc(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    color_profile: ColorProfile,
) ![]u8 {
    return renderTableStyledAlloc(allocator, headers, rows, color_profile, .ascii);
}

test renderAscii {
    const allocator = std.testing.allocator;
    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try renderAscii(
        allocator,
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

fn computeWidths(headers: []const []const u8, rows: []const []const []const u8, allocator: std.mem.Allocator) ![]usize {
    const w = try allocator.alloc(usize, headers.len);
    for (headers, 0..) |h, i| {
        w[i] = term.ansiDisplayWidth(h);
    }
    for (rows) |row| {
        for (row, 0..) |cell, i| {
            const cw = term.ansiDisplayWidth(cell);
            if (cw > w[i]) w[i] = cw;
        }
    }
    return w;
}

fn writeRepeat(writer: *std.Io.Writer, byte: u8, count: usize) !void {
    for (0..count) |_| try writer.writeByte(byte);
}

fn writeRepeatUtf8(writer: *std.Io.Writer, comptime utf8_char: []const u8, count: usize) !void {
    for (0..count) |_| try writer.writeAll(utf8_char);
}

fn writePaddedHeaderCell(
    writer: *std.Io.Writer,
    header: []const u8,
    col_width: usize,
    color_profile: ColorProfile,
) !void {
    const header_style = Style.init().bolded();
    if (color_profile == .none) {
        try writer.writeAll(header);
        const dw = term.ansiDisplayWidth(header);
        if (dw < col_width) try writeRepeat(writer, ' ', col_width - dw);
    } else {
        try header_style.renderWithProfile(header, writer, color_profile);
        const dw = term.ansiDisplayWidth(header);
        if (dw < col_width) try writeRepeat(writer, ' ', col_width - dw);
    }
}

fn writePaddedBodyCell(writer: *std.Io.Writer, cell: []const u8, col_width: usize) !void {
    try writer.writeAll(cell);
    const dw = term.ansiDisplayWidth(cell);
    if (dw < col_width) try writeRepeat(writer, ' ', col_width - dw);
}

fn renderAsciiGrid(
    writer: *std.Io.Writer,
    headers: []const []const u8,
    rows: []const []const []const u8,
    widths: []const usize,
    color_profile: ColorProfile,
) !void {
    try asciiTopOrMidOrBottom(writer, widths);
    try asciiHeaderRow(writer, headers, widths, color_profile);
    try asciiTopOrMidOrBottom(writer, widths);
    for (rows) |row| {
        try asciiBodyRow(writer, row, widths);
    }
    try asciiTopOrMidOrBottom(writer, widths);
}

fn asciiTopOrMidOrBottom(writer: *std.Io.Writer, widths: []const usize) !void {
    try writer.writeAll("+");
    for (widths) |cw| {
        try writeRepeat(writer, '-', cw + 2);
        try writer.writeAll("+");
    }
    try writer.writeAll("\n");
}

fn asciiHeaderRow(
    writer: *std.Io.Writer,
    headers: []const []const u8,
    widths: []const usize,
    color_profile: ColorProfile,
) !void {
    try writer.writeAll("|");
    for (headers, widths) |h, cw| {
        try writer.writeByte(' ');
        try writePaddedHeaderCell(writer, h, cw, color_profile);
        try writer.writeAll(" |");
    }
    try writer.writeAll("\n");
}

fn asciiBodyRow(writer: *std.Io.Writer, cells: []const []const u8, widths: []const usize) !void {
    try writer.writeAll("|");
    for (cells, widths) |cell, cw| {
        try writer.writeByte(' ');
        try writePaddedBodyCell(writer, cell, cw);
        try writer.writeAll(" |");
    }
    try writer.writeAll("\n");
}

fn renderMarkdown(
    writer: *std.Io.Writer,
    headers: []const []const u8,
    rows: []const []const []const u8,
    widths: []const usize,
    color_profile: ColorProfile,
) !void {
    try mdRow(writer, headers, widths, color_profile, true);
    try mdSeparator(writer, widths);
    for (rows) |row| {
        try mdRow(writer, row, widths, .none, false);
    }
}

fn mdRow(
    writer: *std.Io.Writer,
    cells: []const []const u8,
    widths: []const usize,
    color_profile: ColorProfile,
    is_header: bool,
) !void {
    try writer.writeAll("|");
    for (cells, widths) |cell, cw| {
        try writer.writeByte(' ');
        if (is_header) {
            try writePaddedHeaderCell(writer, cell, cw, color_profile);
        } else {
            try writePaddedBodyCell(writer, cell, cw);
        }
        try writer.writeAll(" |");
    }
    try writer.writeAll("\n");
}

fn mdSeparator(writer: *std.Io.Writer, widths: []const usize) !void {
    try writer.writeAll("|");
    for (widths) |cw| {
        const dash_count = @max(3, cw + 2);
        try writeRepeat(writer, '-', dash_count);
        try writer.writeAll("|");
    }
    try writer.writeAll("\n");
}

fn renderUnicodeGrid(
    writer: *std.Io.Writer,
    headers: []const []const u8,
    rows: []const []const []const u8,
    widths: []const usize,
    color_profile: ColorProfile,
) !void {
    try uniTop(writer, widths);
    try uniHeaderRow(writer, headers, widths, color_profile);
    try uniMid(writer, widths);
    for (rows) |row| {
        try uniBodyRow(writer, row, widths);
    }
    try uniBottom(writer, widths);
}

fn uniTop(writer: *std.Io.Writer, widths: []const usize) !void {
    try writer.writeAll("┌");
    for (widths, 0..) |cw, i| {
        try writeRepeatUtf8(writer, "─", cw + 2);
        if (i + 1 < widths.len) try writer.writeAll("┬") else try writer.writeAll("┐");
    }
    try writer.writeAll("\n");
}

fn uniMid(writer: *std.Io.Writer, widths: []const usize) !void {
    try writer.writeAll("├");
    for (widths, 0..) |cw, i| {
        try writeRepeatUtf8(writer, "─", cw + 2);
        if (i + 1 < widths.len) try writer.writeAll("┼") else try writer.writeAll("┤");
    }
    try writer.writeAll("\n");
}

fn uniBottom(writer: *std.Io.Writer, widths: []const usize) !void {
    try writer.writeAll("└");
    for (widths, 0..) |cw, i| {
        try writeRepeatUtf8(writer, "─", cw + 2);
        if (i + 1 < widths.len) try writer.writeAll("┴") else try writer.writeAll("┘");
    }
    try writer.writeAll("\n");
}

fn uniHeaderRow(
    writer: *std.Io.Writer,
    headers: []const []const u8,
    widths: []const usize,
    color_profile: ColorProfile,
) !void {
    try writer.writeAll("│");
    for (headers, widths) |h, cw| {
        try writer.writeByte(' ');
        try writePaddedHeaderCell(writer, h, cw, color_profile);
        try writer.writeAll(" │");
    }
    try writer.writeAll("\n");
}

fn uniBodyRow(writer: *std.Io.Writer, cells: []const []const u8, widths: []const usize) !void {
    try writer.writeAll("│");
    for (cells, widths) |cell, cw| {
        try writer.writeByte(' ');
        try writePaddedBodyCell(writer, cell, cw);
        try writer.writeAll(" │");
    }
    try writer.writeAll("\n");
}

test "ascii table plain" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    var fbw = std.Io.Writer.fixed(&buf);

    try renderAscii(
        allocator,
        &.{ "ALIAS", "COMMIT" },
        &.{
            &.{ "docent", "67bf0813" },
        },
        &fbw,
    );

    const expected =
        "+--------+----------+\n" ++
        "| ALIAS  | COMMIT   |\n" ++
        "+--------+----------+\n" ++
        "| docent | 67bf0813 |\n" ++
        "+--------+----------+\n";
    try std.testing.expectEqualStrings(expected, fbw.buffered());
}

test "ascii table utf8 width padding" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;

    var fbw = std.Io.Writer.fixed(&buf);

    try renderAscii(
        allocator,
        &.{ "名", "x" },
        &.{
            &.{ "你好", "y" },
        },
        &fbw,
    );

    try std.testing.expect(std.mem.indexOf(u8, fbw.buffered(), "| 你好") != null);
}

test "ascii table ansi cell width padding" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try renderAscii(
        allocator,
        &.{ "Name", "State" },
        &.{
            &.{ "\x1b[31mapi\x1b[0m", "ok" },
            &.{ "worker", "warn" },
        },
        &writer,
    );

    try std.testing.expectEqualStrings(
        "+--------+-------+\n" ++
            "| Name   | State |\n" ++
            "+--------+-------+\n" ++
            "| \x1b[31mapi\x1b[0m    | ok    |\n" ++
            "| worker | warn  |\n" ++
            "+--------+-------+\n",
        writer.buffered(),
    );
}

test "markdown table" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    var fbw = std.Io.Writer.fixed(&buf);

    try renderTable(
        allocator,
        &.{ "ALIAS", "COMMIT" },
        &.{
            &.{ "docent", "67bf0813" },
        },
        &fbw,
        .markdown,
    );

    const s = fbw.buffered();
    try std.testing.expect(std.mem.startsWith(u8, s, "| ALIAS "));
    try std.testing.expect(std.mem.indexOf(u8, s, "|---") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "| docent ") != null);
}

test "unicode table structure" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    var fbw = std.Io.Writer.fixed(&buf);

    try renderTable(
        allocator,
        &.{ "A", "B" },
        &.{
            &.{ "1", "2" },
        },
        &fbw,
        .unicode,
    );

    const s = fbw.buffered();
    try std.testing.expect(std.mem.startsWith(u8, s, "┌"));
    try std.testing.expect(std.mem.indexOf(u8, s, "┬") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "│") != null);
    try std.testing.expect(std.mem.endsWith(u8, std.mem.trimEnd(u8, s, "\n"), "┘"));
}

test "ascii table styled header exact output" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try renderAsciiStyled(
        allocator,
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
        },
        &writer,
        .ansi16,
    );

    try std.testing.expectEqualStrings(
        "+------+--------+\n" ++
            "| \x1b[1mName\x1b[0m | \x1b[1mStatus\x1b[0m |\n" ++
            "+------+--------+\n" ++
            "| api  | ok     |\n" ++
            "+------+--------+\n",
        writer.buffered(),
    );
}

test "markdown table exact output" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try renderTable(
        allocator,
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
        },
        &writer,
        .markdown,
    );

    try std.testing.expectEqualStrings(
        "| Name | Status |\n" ++
            "|------|--------|\n" ++
            "| api  | ok     |\n",
        writer.buffered(),
    );
}

fn renderTableAllocTest(
    headers: []const []const u8,
    rows: []const []const []const u8,
    style: TableStyle,
    color_profile: ColorProfile,
) ![]u8 {
    return renderTableStyledAlloc(std.testing.allocator, headers, rows, color_profile, style);
}

test "ascii table renders exact grid output" {
    const rendered = try renderTableAllocTest(
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
            &.{ "cli", "warn" },
        },
        .ascii,
        .none,
    );
    defer std.testing.allocator.free(rendered);

    const expected =
        "+------+--------+\n" ++
        "| Name | Status |\n" ++
        "+------+--------+\n" ++
        "| api  | ok     |\n" ++
        "| cli  | warn   |\n" ++
        "+------+--------+\n";
    try std.testing.expectEqualStrings(expected, rendered);
}

test "markdown table renders exact pipe output" {
    const rendered = try renderTableAllocTest(
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
        },
        .markdown,
        .none,
    );
    defer std.testing.allocator.free(rendered);

    const expected =
        "| Name | Status |\n" ++
        "|------|--------|\n" ++
        "| api  | ok     |\n";
    try std.testing.expectEqualStrings(expected, rendered);
}

test "unicode table renders exact light border output" {
    const rendered = try renderTableAllocTest(
        &.{ "名", "Status" },
        &.{
            &.{ "你好", "ok" },
        },
        .unicode,
        .none,
    );
    defer std.testing.allocator.free(rendered);

    const expected =
        "┌──────┬────────┐\n" ++
        "│ 名   │ Status │\n" ++
        "├──────┼────────┤\n" ++
        "│ 你好 │ ok     │\n" ++
        "└──────┴────────┘\n";
    try std.testing.expectEqualStrings(expected, rendered);
}

test "styled table bolds only header cells" {
    const rendered = try renderTableAllocTest(
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
        },
        .ascii,
        .ansi16,
    );
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[1mName\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[1mStatus\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[1mapi\x1b[0m") == null);
}

test "table rejects rows with wrong column count" {
    const allocator = std.testing.allocator;
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try std.testing.expectError(
        error.TableColumnCountMismatch,
        renderTable(
            allocator,
            &.{ "Name", "Status" },
            &.{
                &.{"api"},
            },
            &writer.writer,
            .ascii,
        ),
    );
}

test "renderTableAlloc returns owned output" {
    const rendered = try renderTableAlloc(
        std.testing.allocator,
        &.{"Name"},
        &.{&.{"Carnaval"}},
        .markdown,
    );
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("| Name     |\n|----------|\n| Carnaval |\n", rendered);
}
