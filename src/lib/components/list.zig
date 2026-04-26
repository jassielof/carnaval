//! List output with stable markers, multiline continuation alignment, and optional ANSI styling.

const std = @import("std");

const ColorProfile = @import("../profile.zig").ColorProfile;
const Style = @import("../Style.zig");
const term = @import("../term.zig");

pub const ListStyle = enum {
    bullet,
    dash,
    asterisk,
    arabic,
    alphabet,
    roman,
};

pub const ListOptions = struct {
    style: ListStyle = .bullet,
    indent: []const u8 = "  ",
    marker_separator: []const u8 = " ",
    marker_style: Style = .{},
    item_style: Style = .{},
    color_profile: ColorProfile = .none,
    align_markers: bool = true,
};

pub const ListItem = struct {
    text: []const u8,
    children: []const ListItem = &.{},

    pub fn init(text: []const u8) ListItem {
        return .{ .text = text };
    }

    pub fn withChildren(text: []const u8, children: []const ListItem) ListItem {
        return .{ .text = text, .children = children };
    }
};

pub fn renderList(items: []const []const u8, writer: *std.Io.Writer, options: ListOptions) !void {
    const marker_width = markerColumnWidth(options.style, items.len, options.align_markers);
    for (items, 0..) |text, i| {
        if (i > 0) try writer.writeByte('\n');
        try renderEntry(text, &.{}, i, 0, marker_width, writer, options);
    }
}

pub fn renderListItems(items: []const ListItem, writer: *std.Io.Writer, options: ListOptions) !void {
    try renderItems(items, 0, writer, options);
}

pub fn renderListAlloc(allocator: std.mem.Allocator, items: []const []const u8, options: ListOptions) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try renderList(items, &writer.writer, options);
    return writer.toOwnedSlice();
}

pub fn renderListItemsAlloc(allocator: std.mem.Allocator, items: []const ListItem, options: ListOptions) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try renderListItems(items, &writer.writer, options);
    return writer.toOwnedSlice();
}

fn renderItems(items: []const ListItem, depth: usize, writer: *std.Io.Writer, options: ListOptions) anyerror!void {
    const marker_width = markerColumnWidth(options.style, items.len, options.align_markers);
    for (items, 0..) |entry, i| {
        if (i > 0) try writer.writeByte('\n');
        try renderEntry(entry.text, entry.children, i, depth, marker_width, writer, options);
    }
}

fn renderEntry(
    text: []const u8,
    children: []const ListItem,
    index: usize,
    depth: usize,
    marker_width: usize,
    writer: *std.Io.Writer,
    options: ListOptions,
) anyerror!void {
    var marker_buf: [32]u8 = undefined;
    const marker = try markerFor(options.style, index, &marker_buf);

    try writeDepthIndent(writer, options, depth);
    try writeMarker(writer, options, marker, marker_width);
    try writer.writeAll(options.marker_separator);
    try writeMultilineText(writer, options, text, depth, marker_width);

    if (children.len > 0) {
        try writer.writeByte('\n');
        try renderItems(children, depth + 1, writer, options);
    }
}

fn writeDepthIndent(writer: *std.Io.Writer, options: ListOptions, depth: usize) !void {
    for (0..depth) |_| try writer.writeAll(options.indent);
}

fn writeMarker(writer: *std.Io.Writer, options: ListOptions, marker: []const u8, marker_width: usize) !void {
    const visible = term.ansiDisplayWidth(marker);
    if (options.align_markers and visible < marker_width) {
        try writeRepeat(writer, ' ', marker_width - visible);
    }

    try options.marker_style.renderWithProfile(marker, writer, options.color_profile);
}

fn writeMultilineText(
    writer: *std.Io.Writer,
    options: ListOptions,
    text: []const u8,
    depth: usize,
    marker_width: usize,
) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) {
            try writer.writeByte('\n');
            try writeDepthIndent(writer, options, depth);
            try writeRepeat(writer, ' ', marker_width);
            try writeRepeat(writer, ' ', term.ansiDisplayWidth(options.marker_separator));
        }
        first = false;

        try options.item_style.renderWithProfile(line, writer, options.color_profile);
    }
}

fn markerColumnWidth(style: ListStyle, sibling_count: usize, should_align: bool) usize {
    if (!should_align or sibling_count == 0) return 0;

    var width: usize = 0;
    for (0..sibling_count) |i| {
        width = @max(width, markerWidth(style, i));
    }
    return width;
}

fn markerWidth(style: ListStyle, index: usize) usize {
    return switch (style) {
        .bullet, .dash, .asterisk => 1,
        .arabic => decimalDigits(index + 1) + 1,
        .alphabet => alphabetLetterCount(index) + 1,
        .roman => romanWidth(index + 1) + 1,
    };
}

fn markerFor(style: ListStyle, index: usize, buf: []u8) ![]const u8 {
    return switch (style) {
        .bullet => "•",
        .dash => "-",
        .asterisk => "*",
        .arabic => try std.fmt.bufPrint(buf, "{d}.", .{index + 1}),
        .alphabet => try alphabetMarker(index, buf),
        .roman => try romanMarker(index + 1, buf),
    };
}

fn alphabetMarker(index: usize, buf: []u8) ![]const u8 {
    var letters: [16]u8 = undefined;
    var len: usize = 0;
    var n = index;

    while (true) {
        letters[len] = 'A' + @as(u8, @intCast(n % 26));
        len += 1;
        if (n < 26) break;
        n = n / 26 - 1;
    }

    if (len + 1 > buf.len) return error.NoSpaceLeft;
    for (0..len) |i| {
        buf[i] = letters[len - 1 - i];
    }
    buf[len] = '.';
    return buf[0 .. len + 1];
}

fn romanMarker(number: usize, buf: []u8) ![]const u8 {
    const numeral = try romanNumeral(number, buf[0 .. buf.len - 1]);
    buf[numeral.len] = '.';
    return buf[0 .. numeral.len + 1];
}

fn romanNumeral(number: usize, buf: []u8) ![]const u8 {
    const symbols = [_]struct { value: usize, text: []const u8 }{
        .{ .value = 1000, .text = "M" },
        .{ .value = 900, .text = "CM" },
        .{ .value = 500, .text = "D" },
        .{ .value = 400, .text = "CD" },
        .{ .value = 100, .text = "C" },
        .{ .value = 90, .text = "XC" },
        .{ .value = 50, .text = "L" },
        .{ .value = 40, .text = "XL" },
        .{ .value = 10, .text = "X" },
        .{ .value = 9, .text = "IX" },
        .{ .value = 5, .text = "V" },
        .{ .value = 4, .text = "IV" },
        .{ .value = 1, .text = "I" },
    };

    var n = number;
    var out_len: usize = 0;
    for (symbols) |symbol| {
        while (n >= symbol.value) {
            if (out_len + symbol.text.len > buf.len) return error.NoSpaceLeft;
            @memcpy(buf[out_len .. out_len + symbol.text.len], symbol.text);
            out_len += symbol.text.len;
            n -= symbol.value;
        }
    }

    return buf[0..out_len];
}

fn romanWidth(number: usize) usize {
    var buf: [31]u8 = undefined;
    const numeral = romanNumeral(number, &buf) catch return 0;
    return numeral.len;
}

fn alphabetLetterCount(index: usize) usize {
    var n = index;
    var count: usize = 1;
    while (n >= 26) {
        count += 1;
        n = n / 26 - 1;
    }
    return count;
}

fn decimalDigits(number: usize) usize {
    var n = number;
    var digits: usize = 1;
    while (n >= 10) {
        digits += 1;
        n /= 10;
    }
    return digits;
}

fn writeRepeat(writer: *std.Io.Writer, byte: u8, count: usize) !void {
    for (0..count) |_| try writer.writeByte(byte);
}

test ListItem {
    const items = [_]ListItem{ListItem.withChildren("parent", &.{ListItem.init("child")})};
    const out = try renderListItemsAlloc(std.testing.allocator, &items, .{ .style = .dash });
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("- parent\n  - child", out);
}

test "list renders bullet items" {
    const out = try renderListAlloc(std.testing.allocator, &.{ "alpha", "beta" }, .{});
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("• alpha\n• beta", out);
}

test "list renders aligned arabic markers" {
    const out = try renderListAlloc(
        std.testing.allocator,
        &.{ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" },
        .{ .style = .arabic },
    );
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings(
        " 1. one\n" ++
            " 2. two\n" ++
            " 3. three\n" ++
            " 4. four\n" ++
            " 5. five\n" ++
            " 6. six\n" ++
            " 7. seven\n" ++
            " 8. eight\n" ++
            " 9. nine\n" ++
            "10. ten",
        out,
    );
}

test "list renders alphabet and roman markers" {
    var buf: [32]u8 = undefined;

    try std.testing.expectEqualStrings("A.", try markerFor(.alphabet, 0, &buf));
    try std.testing.expectEqualStrings("Z.", try markerFor(.alphabet, 25, &buf));
    try std.testing.expectEqualStrings("AA.", try markerFor(.alphabet, 26, &buf));
    try std.testing.expectEqualStrings("I.", try markerFor(.roman, 0, &buf));
    try std.testing.expectEqualStrings("IX.", try markerFor(.roman, 8, &buf));
    try std.testing.expectEqualStrings("XL.", try markerFor(.roman, 39, &buf));
}

test "list aligns multiline continuations under item text" {
    const out = try renderListAlloc(std.testing.allocator, &.{"first line\nsecond line"}, .{ .style = .dash });
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("- first line\n  second line", out);
}

test "list styles marker and item independently" {
    const out = try renderListAlloc(std.testing.allocator, &.{"ok"}, .{
        .style = .dash,
        .marker_style = Style.init().fg(.{ .ansi16 = .red }),
        .item_style = Style.init().bolded(),
        .color_profile = .ansi16,
    });
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("\x1b[31m-\x1b[0m \x1b[1mok\x1b[0m", out);
}
