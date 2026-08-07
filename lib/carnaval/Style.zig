//! Immutable ANSI/SGR styling for terminal strings (colors and text attributes).
//!
//! Builder methods return a new `Style`; nothing is mutated in place. When rendering with
//! `ColorProfile.none`, or when no colors or attributes are set, output is plain text (no escapes).

const std = @import("std");

const Color = @import("color.zig").Color;
const ColorProfile = @import("profile.zig").ColorProfile;
const escape = @import("escape.zig");
const profile = @import("profile.zig");

const Style = @This();

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
/// When true, emit dim/faint (SGR 2) until reset.
dim: bool = false,
/// When true, emit strikethrough (SGR 9) until reset.
strikethrough: bool = false,

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
    if (color_profile == .none or !self.hasFormatting()) {
        try writer.writeAll(text);
        return;
    }

    var wrote_any = false;

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
        try writer.writeAll("\x1b[4m");
        wrote_any = true;
    }
    if (self.strikethrough) {
        try writer.writeAll("\x1b[9m");
        wrote_any = true;
    }
    if (self.fg_color) |c| {
        if (try c.emitFg(writer, color_profile)) wrote_any = true;
    }
    if (self.bg_color) |c| {
        if (try c.emitBg(writer, color_profile)) wrote_any = true;
    }

    try writer.writeAll(text);
    if (wrote_any) try writer.writeAll(escape.reset);
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
        self.bold or
        self.italic or
        self.underline or
        self.dim or
        self.strikethrough;
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
