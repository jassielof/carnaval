//! Immutable ANSI/SGR styling for terminal strings (colors and text attributes).
//!
//! Builder methods return a new `Style`; nothing is mutated in place. When rendering with
//! `ColorProfile.none`, or when no colors or attributes are set, output is plain text (no escapes).

const std = @import("std");

const Color = @import("color.zig").Color;
const ColorProfile = @import("profile.zig").ColorProfile;
const escape = @import("escape.zig");
const profile = @import("profile.zig");
const Border = @import("Border.zig");
const Insets = @import("Insets.zig");
const layout = @import("layout.zig");

const Style = @This();

/// The UnderlineStyle enumeration selects the terminal underline variant.
pub const UnderlineStyle = enum {
    none,
    single,
    double,
    curly,
    dotted,
    dashed,
};

/// Foreground color; `null` uses the terminal default.
fg_color: ?Color = null,
/// Background color; `null` uses the terminal default.
bg_color: ?Color = null,
/// When true, emit bold (SGR 1) until reset.
bold: bool = false,
/// When true, emit italic (SGR 3) until reset.
italic: bool = false,
/// When true, emit underline (SGR 4) until reset.
underline: bool = false,
/// The selected underline variant.
underline_style: UnderlineStyle = .single,
/// The optional underline color.
underline_color: ?Color = null,
/// When true, emit dim/faint (SGR 2) until reset.
dim: bool = false,
/// When true, emit strikethrough (SGR 9) until reset.
strikethrough: bool = false,
/// When true, exchange the foreground and background colors (SGR 7).
reverse: bool = false,
/// When true, emit slow blink (SGR 5).
blink: bool = false,
/// The optional OSC 8 hyperlink target.
hyperlink: ?[]const u8 = null,
padding: Insets = .{},
margin: Insets = .{},
width_cells: ?usize = null,
height_cells: ?usize = null,
alignment: layout.HorizontalAlignment = .left,
border: ?Border = null,
border_top: bool = true,
border_right: bool = true,
border_bottom: bool = true,
border_left: bool = true,

/// Returns a style with no colors or attributes.
pub fn init() Style {
    return .{};
}

/// Sets the foreground color (replaces any previous foreground).
pub fn fg(self: Style, c: Color) Style {
    var out = self;
    out.fg_color = c;
    return out;
}

/// Sets the background color (replaces any previous background).
pub fn bg(self: Style, c: Color) Style {
    var out = self;
    out.bg_color = c;
    return out;
}

/// Enables or disables bold (SGR 1).
pub fn withBold(self: Style, enabled: bool) Style {
    var out = self;
    out.bold = enabled;
    return out;
}

/// Enables or disables italic (SGR 3).
pub fn withItalic(self: Style, enabled: bool) Style {
    var out = self;
    out.italic = enabled;
    return out;
}

/// Enables or disables underline (SGR 4).
pub fn withUnderline(self: Style, enabled: bool) Style {
    var out = self;
    out.underline = enabled;
    return out;
}

/// The withUnderlineStyle function enables an underline variant, or disables underlining with `.none`.
pub fn withUnderlineStyle(self: Style, style: UnderlineStyle) Style {
    var out = self;
    out.underline_style = style;
    out.underline = style != .none;
    return out;
}

/// The withUnderlineColor function sets the underline color.
pub fn withUnderlineColor(self: Style, color: ?Color) Style {
    var out = self;
    out.underline_color = color;
    return out;
}

/// Enables or disables dim/faint (SGR 2).
pub fn withDim(self: Style, enabled: bool) Style {
    var out = self;
    out.dim = enabled;
    return out;
}

/// Enables or disables strikethrough (SGR 9).
pub fn withStrikethrough(self: Style, enabled: bool) Style {
    var out = self;
    out.strikethrough = enabled;
    return out;
}

/// The withReverse function enables or disables reverse video.
pub fn withReverse(self: Style, enabled: bool) Style {
    var out = self;
    out.reverse = enabled;
    return out;
}

/// The withBlink function enables or disables slow blink.
pub fn withBlink(self: Style, enabled: bool) Style {
    var out = self;
    out.blink = enabled;
    return out;
}

/// The withHyperlink function sets the OSC 8 hyperlink target. Pass `null` to remove it.
pub fn withHyperlink(self: Style, url: ?[]const u8) Style {
    var out = self;
    out.hyperlink = url;
    return out;
}

/// The withPadding function sets equal padding on every edge.
pub fn withPadding(self: Style, amount: usize) Style {
    var out = self;
    out.padding = Insets.all(amount);
    return out;
}

/// The withPaddingEdges function sets the padding edges explicitly.
pub fn withPaddingEdges(self: Style, padding: Insets) Style {
    var out = self;
    out.padding = padding;
    return out;
}

/// The withMargin function sets equal outer margin on every edge.
pub fn withMargin(self: Style, amount: usize) Style {
    var out = self;
    out.margin = Insets.all(amount);
    return out;
}

/// The withMarginEdges function sets the outer margin edges explicitly.
pub fn withMarginEdges(self: Style, margin: Insets) Style {
    var out = self;
    out.margin = margin;
    return out;
}

/// The withWidth function sets the minimum content width in terminal cells.
pub fn withWidth(self: Style, cells: ?usize) Style {
    var out = self;
    out.width_cells = cells;
    return out;
}

/// The withHeight function sets the minimum content height in terminal lines.
pub fn withHeight(self: Style, lines: ?usize) Style {
    var out = self;
    out.height_cells = lines;
    return out;
}

/// The withAlignment function sets horizontal content alignment inside a fixed width.
pub fn withAlignment(self: Style, value: layout.HorizontalAlignment) Style {
    var out = self;
    out.alignment = value;
    return out;
}

/// The withBorder function sets a border and enables every edge.
pub fn withBorder(self: Style, value: ?Border) Style {
    var out = self;
    out.border = value;
    out.border_top = true;
    out.border_right = true;
    out.border_bottom = true;
    out.border_left = true;
    return out;
}

/// The withBorderEdges function sets which edges of the current border are rendered.
pub fn withBorderEdges(self: Style, top: bool, right: bool, bottom: bool, left: bool) Style {
    var out = self;
    out.border_top = top;
    out.border_right = right;
    out.border_bottom = bottom;
    out.border_left = left;
    return out;
}

/// Shorthand for `withBold(true)`.
pub fn bolded(self: Style) Style {
    return self.withBold(true);
}

/// Shorthand for `withItalic(true)`.
pub fn italicized(self: Style) Style {
    return self.withItalic(true);
}

/// Shorthand for `withUnderline(true)`.
pub fn underlined(self: Style) Style {
    return self.withUnderline(true);
}

/// The reversed function enables reverse video.
pub fn reversed(self: Style) Style {
    return self.withReverse(true);
}

/// The blinking function enables slow blink.
pub fn blinking(self: Style) Style {
    return self.withBlink(true);
}

/// Shorthand for `withDim(true)`.
pub fn dimmed(self: Style) Style {
    return self.withDim(true);
}

/// Shorthand for `withStrikethrough(true)`.
pub fn striked(self: Style) Style {
    return self.withStrikethrough(true);
}

/// Writes `text` using `colorProfile()` from `profile.zig` (typically stdout capability).
pub fn render(self: Style, text: []const u8, writer: *std.Io.Writer) !void {
    try self.renderWithProfile(text, writer, profile.colorProfile());
}

/// Writes `text` with ANSI prefixes and a trailing reset when `color_profile` is not `.none`
/// and at least one attribute or color is active.
pub fn renderWithProfile(self: Style, text: []const u8, writer: *std.Io.Writer, color_profile: ColorProfile) !void {
    if (self.hasFrame()) {
        const framed = try self.frameAlloc(text, std.heap.page_allocator);
        defer std.heap.page_allocator.free(framed);
        try self.renderSgrWithProfile(framed, writer, color_profile);
        return;
    }
    try self.renderSgrWithProfile(text, writer, color_profile);
}

fn renderSgrWithProfile(self: Style, text: []const u8, writer: *std.Io.Writer, color_profile: ColorProfile) !void {
    if (color_profile == .none or (!self.hasFormatting() and self.hyperlink == null)) {
        try writer.writeAll(text);
        return;
    }

    var wrote_any = false;
    const write_link = color_profile != .none and self.hyperlink != null;
    if (write_link) try writer.print("\x1b]8;;{s}\x1b\\", .{self.hyperlink.?});

    if (self.bold) {
        try writer.writeAll("\x1b[1m");
        wrote_any = true;
    }
    if (self.dim) {
        try writer.writeAll("\x1b[2m");
        wrote_any = true;
    }
    if (self.italic) {
        try writer.writeAll("\x1b[3m");
        wrote_any = true;
    }
    if (self.underline) {
        try writer.writeAll(underlineSequence(self.underline_style));
        wrote_any = true;
    }
    if (self.strikethrough) {
        try writer.writeAll("\x1b[9m");
        wrote_any = true;
    }
    if (self.reverse) {
        try writer.writeAll("\x1b[7m");
        wrote_any = true;
    }
    if (self.blink) {
        try writer.writeAll("\x1b[5m");
        wrote_any = true;
    }
    if (self.fg_color) |c| {
        if (try c.emitFg(writer, color_profile)) wrote_any = true;
    }
    if (self.bg_color) |c| {
        if (try c.emitBg(writer, color_profile)) wrote_any = true;
    }
    if (self.underline_color) |c| {
        if (try c.emitUnderline(writer, color_profile)) wrote_any = true;
    }

    try writer.writeAll(text);
    if (wrote_any) try writer.writeAll(escape.reset);
    if (write_link) try writer.writeAll("\x1b]8;;\x1b\\");
}

/// Like `render`, but returns an owned buffer allocated with `allocator`.
pub fn renderAlloc(self: Style, text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return self.renderAllocWithProfile(text, allocator, profile.colorProfile());
}

/// Like `renderWithProfile`, but returns an owned buffer allocated with `allocator`.
pub fn renderAllocWithProfile(self: Style, text: []const u8, allocator: std.mem.Allocator, color_profile: ColorProfile) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try self.renderWithProfile(text, &writer.writer, color_profile);
    return writer.toOwnedSlice();
}

fn hasFormatting(self: Style) bool {
    return self.fg_color != null or
        self.bg_color != null or
        self.underline_color != null or
        self.bold or
        self.italic or
        self.underline or
        self.dim or
        self.strikethrough or
        self.reverse or
        self.blink;
}

fn hasFrame(self: Style) bool {
    return self.padding.horizontal() != 0 or self.padding.vertical() != 0 or
        self.margin.horizontal() != 0 or self.margin.vertical() != 0 or
        self.width_cells != null or self.height_cells != null or self.border != null;
}

fn frameAlloc(self: Style, text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const content_width = @max(self.width_cells orelse 0, layout.width(text));
    const content_height = @max(self.height_cells orelse 0, layout.height(text));
    const border = self.border;
    const left_border = border != null and self.border_left;
    const right_border = border != null and self.border_right;
    const top_border = border != null and self.border_top;
    const bottom_border = border != null and self.border_bottom;
    const inner_width = content_width + self.padding.horizontal();

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    var emitted_lines: usize = 0;
    const total_lines = self.margin.vertical() + @as(usize, @intFromBool(top_border)) + self.padding.vertical() + content_height + @as(usize, @intFromBool(bottom_border));

    const write_line_prefix = struct {
        fn call(w: *std.Io.Writer, margin_left: usize, has_left: bool, b: ?Border) !void {
            for (0..margin_left) |_| try w.writeByte(' ');
            if (has_left) try w.writeAll(b.?.left);
        }
    }.call;
    const finish_line = struct {
        fn call(w: *std.Io.Writer, margin_right: usize, has_right: bool, b: ?Border, last: bool) !void {
            if (has_right) try w.writeAll(b.?.right);
            for (0..margin_right) |_| try w.writeByte(' ');
            if (!last) try w.writeByte('\n');
        }
    }.call;
    const write_fill = struct {
        fn call(w: *std.Io.Writer, count: usize) !void {
            for (0..count) |_| try w.writeByte(' ');
        }
    }.call;

    for (0..self.margin.top) |_| {
        try write_fill(&out.writer, self.margin.left + inner_width + @as(usize, @intFromBool(left_border)) + @as(usize, @intFromBool(right_border)) + self.margin.right);
        emitted_lines += 1;
        if (emitted_lines < total_lines) try out.writer.writeByte('\n');
    }
    if (top_border) {
        try write_fill(&out.writer, self.margin.left);
        try out.writer.writeAll(border.?.top_left);
        for (0..inner_width) |_| try out.writer.writeAll(border.?.top);
        try out.writer.writeAll(border.?.top_right);
        try write_fill(&out.writer, self.margin.right);
        emitted_lines += 1;
        if (emitted_lines < total_lines) try out.writer.writeByte('\n');
    }
    for (0..self.padding.top) |_| {
        try write_line_prefix(&out.writer, self.margin.left, left_border, border);
        try write_fill(&out.writer, inner_width);
        try finish_line(&out.writer, self.margin.right, right_border, border, emitted_lines + 1 == total_lines);
        emitted_lines += 1;
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_index: usize = 0;
    while (line_index < content_height) : (line_index += 1) {
        const line = lines.next() orelse "";
        const missing = content_width - layout.width(line);
        const left = switch (self.alignment) {
            .left => 0,
            .center => missing / 2,
            .right => missing,
        };
        try write_line_prefix(&out.writer, self.margin.left, left_border, border);
        try write_fill(&out.writer, self.padding.left + left);
        try out.writer.writeAll(line);
        try write_fill(&out.writer, missing - left + self.padding.right);
        try finish_line(&out.writer, self.margin.right, right_border, border, emitted_lines + 1 == total_lines);
        emitted_lines += 1;
    }
    for (0..self.padding.bottom) |_| {
        try write_line_prefix(&out.writer, self.margin.left, left_border, border);
        try write_fill(&out.writer, inner_width);
        try finish_line(&out.writer, self.margin.right, right_border, border, emitted_lines + 1 == total_lines);
        emitted_lines += 1;
    }
    if (bottom_border) {
        try write_fill(&out.writer, self.margin.left);
        try out.writer.writeAll(border.?.bottom_left);
        for (0..inner_width) |_| try out.writer.writeAll(border.?.bottom);
        try out.writer.writeAll(border.?.bottom_right);
        try write_fill(&out.writer, self.margin.right);
    }
    return out.toOwnedSlice();
}

fn underlineSequence(style: UnderlineStyle) []const u8 {
    return switch (style) {
        .none => "",
        .single => "\x1b[4m",
        .double => "\x1b[4:2m",
        .curly => "\x1b[4:3m",
        .dotted => "\x1b[4:4m",
        .dashed => "\x1b[4:5m",
    };
}

test Style {
    const allocator = std.testing.allocator;
    const style = Style.init().underlined().fg(.{ .ansi16 = .cyan });

    const rendered = try style.renderAllocWithProfile("docs", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("\x1b[4m\x1b[36mdocs\x1b[0m", rendered);
}

test "render with reset" {
    const allocator = std.testing.allocator;
    const style = Style.init().fg(.{ .ansi16 = .red }).bolded();
    const rendered = try style.renderAllocWithProfile("hi", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("\x1b[1m\x1b[31mhi\x1b[0m", rendered);
}

test "render plain when profile none" {
    const allocator = std.testing.allocator;
    const style = Style.init().fg(.{ .ansi16 = .red }).bolded();
    const rendered = try style.renderAllocWithProfile("hi", allocator, .none);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("hi", rendered);
}

test "render all attributes foreground and background in stable order" {
    const allocator = std.testing.allocator;
    const style = Style.init()
        .bolded()
        .dimmed()
        .italicized()
        .underlined()
        .striked()
        .fg(.{ .ansi16 = .bright_white })
        .bg(.{ .ansi16 = .black });

    const rendered = try style.renderAllocWithProfile("all", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[1m\x1b[2m\x1b[3m\x1b[4m\x1b[9m\x1b[97m\x1b[40mall\x1b[0m",
        rendered,
    );
}

test "render ansi256 and true color escape codes" {
    const allocator = std.testing.allocator;
    const ansi_style = Style.init().fg(.{ .ansi256 = 42 }).bg(.{ .ansi256 = 99 });
    const ansi_rendered = try ansi_style.renderAllocWithProfile("x", allocator, .ansi256);
    defer allocator.free(ansi_rendered);

    try std.testing.expectEqualStrings("\x1b[38;5;42m\x1b[48;5;99mx\x1b[0m", ansi_rendered);

    const true_color_style = Style.init().fg(Color.rgb(1, 2, 3)).bg(Color.rgb(4, 5, 6));
    const true_color_rendered = try true_color_style.renderAllocWithProfile("x", allocator, .true_color);
    defer allocator.free(true_color_rendered);

    try std.testing.expectEqualStrings("\x1b[38;2;1;2;3m\x1b[48;2;4;5;6mx\x1b[0m", true_color_rendered);
}

test "render color none writes text without reset" {
    const allocator = std.testing.allocator;
    const style = Style.init().fg(.none).bg(.none);

    const rendered = try style.renderAllocWithProfile("plain", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("plain", rendered);
}

test "render fixed writer exact output" {
    const style = Style.init().bolded().fg(.{ .ansi16 = .green });
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try style.renderWithProfile("ok", &writer, .ansi16);

    try std.testing.expectEqualStrings("\x1b[1m\x1b[32mok\x1b[0m", writer.buffered());
}

test "style render uses reset" {
    const allocator = std.testing.allocator;
    const st = Style.init()
        .fg(.{ .ansi16 = .green })
        .withUnderline(true);

    const rendered = try st.renderAllocWithProfile("ok", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.endsWith(u8, rendered, "\x1b[0m"));
}

test "style render exact ansi16 escape sequence order" {
    const allocator = std.testing.allocator;
    const style = Style.init()
        .bolded()
        .dimmed()
        .italicized()
        .underlined()
        .striked()
        .fg(.{ .ansi16 = .red })
        .bg(.{ .ansi16 = .blue });

    const rendered = try style.renderAllocWithProfile("go", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[1m\x1b[2m\x1b[3m\x1b[4m\x1b[9m\x1b[31m\x1b[44mgo\x1b[0m",
        rendered,
    );
}

test "style render exact true color foreground and background" {
    const allocator = std.testing.allocator;
    const style = Style.init()
        .fg(Color.rgb(12, 34, 56))
        .bg(Color.rgb(200, 201, 202));

    const rendered = try style.renderAllocWithProfile("rgb", allocator, .true_color);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[38;2;12;34;56m\x1b[48;2;200;201;202mrgb\x1b[0m",
        rendered,
    );
}

test "style render downsampled ansi256 profile" {
    const allocator = std.testing.allocator;
    const style = Style.init()
        .fg(Color.rgb(255, 0, 0))
        .bg(.{ .ansi16 = .bright_blue });

    const rendered = try style.renderAllocWithProfile("color", allocator, .ansi256);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[38;5;196m\x1b[48;5;12mcolor\x1b[0m",
        rendered,
    );
}

test "style render writes plain text when profile disables color" {
    const allocator = std.testing.allocator;
    const style = Style.init()
        .bolded()
        .fg(.{ .ansi16 = .green });

    const rendered = try style.renderAllocWithProfile("plain", allocator, .none);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("plain", rendered);
}

test "style writer output matches allocating render" {
    const allocator = std.testing.allocator;
    const style = Style.init()
        .underlined()
        .fg(.{ .ansi256 = 42 });
    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try style.renderWithProfile("writer", &writer, .ansi256);

    const allocated = try style.renderAllocWithProfile("writer", allocator, .ansi256);
    defer allocator.free(allocated);

    try std.testing.expectEqualStrings(allocated, writer.buffered());
}

test "Style renders extended attributes and hyperlinks" {
    const rendered = try Style.init()
        .withUnderlineStyle(.curly)
        .reversed()
        .blinking()
        .withHyperlink("https://example.com")
        .renderAllocWithProfile("link", std.testing.allocator, .true_color);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b]8;;https://example.com\x1b\\\x1b[4:3m\x1b[7m\x1b[5mlink\x1b[0m\x1b]8;;\x1b\\",
        rendered,
    );
}

test "Style renders padding, alignment, and a border as one frame" {
    const style = Style.init()
        .withWidth(4)
        .withPaddingEdges(.{ .left = 1, .right = 1 })
        .withAlignment(.center)
        .withBorder(Border.ascii());
    const rendered = try style.renderAllocWithProfile("go", std.testing.allocator, .none);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "+------+\n" ++
            "|  go  |\n" ++
            "+------+",
        rendered,
    );
}
