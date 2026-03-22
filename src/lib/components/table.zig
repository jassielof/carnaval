//! Tabular output: ASCII grid (portable), Markdown pipe tables (GFM), and Unicode
//! light borders similar to Charmbracelet Lip Gloss `Border.Normal`.
//!
//! On Windows consoles, UTF-8 output is enabled automatically the first time Carnaval
//! talks to the console (`terminalWidth*`, `colorProfile*`, or a Unicode table).

const std = @import("std");
const ColorProfile = @import("../profile.zig").ColorProfile;
const Style = @import("../style.zig").Style;
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
    writer: anytype,
    style: TableStyle,
) !void {
    return renderTableStyled(allocator, headers, rows, writer, .none, style);
}

/// Renders a table. Header row uses bold when `color_profile` is not `.none`.
pub fn renderTableStyled(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    color_profile: ColorProfile,
    style: TableStyle,
) !void {
    if (headers.len == 0) return;

    for (rows) |row| {
        if (row.len != headers.len) return error.TableColumnCountMismatch;
    }

    if (style == .unicode) {
        term.prepareWindowsConsoleIfNeeded(std.fs.File.stdout().handle);
    }

    const widths = try computeWidths(headers, rows, allocator);
    defer allocator.free(widths);

    switch (style) {
        .ascii => try renderAsciiGrid(writer, headers, rows, widths, color_profile),
        .markdown => try renderMarkdown(writer, headers, rows, widths, color_profile),
        .unicode => try renderUnicodeGrid(writer, headers, rows, widths, color_profile),
    }
}

/// Renders an ASCII `+---+' table (styled header when color is enabled).
pub fn renderAscii(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
) !void {
    return renderTable(allocator, headers, rows, writer, .ascii);
}

/// Same as `renderAscii` with explicit color profile for the header row.
pub fn renderAsciiStyled(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    color_profile: ColorProfile,
) !void {
    return renderTableStyled(allocator, headers, rows, writer, color_profile, .ascii);
}

fn computeWidths(headers: []const []const u8, rows: []const []const []const u8, allocator: std.mem.Allocator) ![]usize {
    const w = try allocator.alloc(usize, headers.len);
    for (headers, 0..) |h, i| {
        w[i] = term.utf8DisplayWidth(h);
    }
    for (rows) |row| {
        for (row, 0..) |cell, i| {
            const cw = term.utf8DisplayWidth(cell);
            if (cw > w[i]) w[i] = cw;
        }
    }
    return w;
}

fn writeRepeat(writer: anytype, byte: u8, count: usize) !void {
    for (0..count) |_| try writer.writeByte(byte);
}

fn writeRepeatUtf8(writer: anytype, comptime utf8_char: []const u8, count: usize) !void {
    for (0..count) |_| try writer.writeAll(utf8_char);
}

fn writePaddedHeaderCell(
    writer: anytype,
    header: []const u8,
    col_width: usize,
    color_profile: ColorProfile,
) !void {
    const header_style = Style.init().bolded();
    if (color_profile == .none) {
        try writer.writeAll(header);
        const dw = term.utf8DisplayWidth(header);
        if (dw < col_width) try writeRepeat(writer, ' ', col_width - dw);
    } else {
        try header_style.renderWithProfile(header, writer, color_profile);
        const dw = term.utf8DisplayWidth(header);
        if (dw < col_width) try writeRepeat(writer, ' ', col_width - dw);
    }
}

fn writePaddedBodyCell(writer: anytype, cell: []const u8, col_width: usize) !void {
    try writer.writeAll(cell);
    const dw = term.utf8DisplayWidth(cell);
    if (dw < col_width) try writeRepeat(writer, ' ', col_width - dw);
}

// --- ASCII ------------------------------------------------------------------

fn renderAsciiGrid(
    writer: anytype,
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

fn asciiTopOrMidOrBottom(writer: anytype, widths: []const usize) !void {
    try writer.writeAll("+");
    for (widths) |cw| {
        try writeRepeat(writer, '-', cw + 2);
        try writer.writeAll("+");
    }
    try writer.writeAll("\n");
}

fn asciiHeaderRow(
    writer: anytype,
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

fn asciiBodyRow(writer: anytype, cells: []const []const u8, widths: []const usize) !void {
    try writer.writeAll("|");
    for (cells, widths) |cell, cw| {
        try writer.writeByte(' ');
        try writePaddedBodyCell(writer, cell, cw);
        try writer.writeAll(" |");
    }
    try writer.writeAll("\n");
}

// --- Markdown (GFM) ---------------------------------------------------------

fn renderMarkdown(
    writer: anytype,
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
    writer: anytype,
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

fn mdSeparator(writer: anytype, widths: []const usize) !void {
    try writer.writeAll("|");
    for (widths) |cw| {
        const dash_count = @max(3, cw + 2);
        try writeRepeat(writer, '-', dash_count);
        try writer.writeAll("|");
    }
    try writer.writeAll("\n");
}

// --- Unicode (Lip Gloss Normal / light box) ---------------------------------

fn renderUnicodeGrid(
    writer: anytype,
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

fn uniTop(writer: anytype, widths: []const usize) !void {
    try writer.writeAll("┌");
    for (widths, 0..) |cw, i| {
        try writeRepeatUtf8(writer, "─", cw + 2);
        if (i + 1 < widths.len) try writer.writeAll("┬") else try writer.writeAll("┐");
    }
    try writer.writeAll("\n");
}

fn uniMid(writer: anytype, widths: []const usize) !void {
    try writer.writeAll("├");
    for (widths, 0..) |cw, i| {
        try writeRepeatUtf8(writer, "─", cw + 2);
        if (i + 1 < widths.len) try writer.writeAll("┼") else try writer.writeAll("┤");
    }
    try writer.writeAll("\n");
}

fn uniBottom(writer: anytype, widths: []const usize) !void {
    try writer.writeAll("└");
    for (widths, 0..) |cw, i| {
        try writeRepeatUtf8(writer, "─", cw + 2);
        if (i + 1 < widths.len) try writer.writeAll("┴") else try writer.writeAll("┘");
    }
    try writer.writeAll("\n");
}

fn uniHeaderRow(
    writer: anytype,
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

fn uniBodyRow(writer: anytype, cells: []const []const u8, widths: []const usize) !void {
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
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    try renderAscii(
        allocator,
        &.{ "ALIAS", "COMMIT" },
        &.{
            &.{ "docent", "67bf0813" },
        },
        w,
    );

    const expected =
        "+--------+----------+\n" ++
        "| ALIAS  | COMMIT   |\n" ++
        "+--------+----------+\n" ++
        "| docent | 67bf0813 |\n" ++
        "+--------+----------+\n";
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "ascii table utf8 width padding" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    try renderAscii(
        allocator,
        &.{ "名", "x" },
        &.{
            &.{ "你好", "y" },
        },
        w,
    );

    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "| 你好") != null);
}

test "markdown table" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    try renderTable(
        allocator,
        &.{ "ALIAS", "COMMIT" },
        &.{
            &.{ "docent", "67bf0813" },
        },
        w,
        .markdown,
    );

    const s = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, s, "| ALIAS "));
    try std.testing.expect(std.mem.indexOf(u8, s, "|---") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "| docent ") != null);
}

test "unicode table structure" {
    const allocator = std.testing.allocator;
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    try renderTable(
        allocator,
        &.{ "A", "B" },
        &.{
            &.{ "1", "2" },
        },
        w,
        .unicode,
    );

    const s = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, s, "┌"));
    try std.testing.expect(std.mem.indexOf(u8, s, "┬") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "│") != null);
    try std.testing.expect(std.mem.endsWith(u8, std.mem.trimRight(u8, s, "\n"), "┘"));
}
