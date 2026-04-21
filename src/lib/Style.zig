const std = @import("std");

const Color = @import("color.zig").Color;
const ColorProfile = @import("profile.zig").ColorProfile;
const escape = @import("escape.zig");
const ListSink = @import("ListSink.zig");
const profile = @import("profile.zig");

const Style = @This();

fg_color: ?Color = null,
bg_color: ?Color = null,
bold: bool = false,
italic: bool = false,
underline: bool = false,
dim: bool = false,
strikethrough: bool = false,

pub fn init() Style {
    return .{};
}

pub fn fg(self: Style, c: Color) Style {
    var out = self;
    out.fg_color = c;
    return out;
}

pub fn bg(self: Style, c: Color) Style {
    var out = self;
    out.bg_color = c;
    return out;
}

pub fn withBold(self: Style, enabled: bool) Style {
    var out = self;
    out.bold = enabled;
    return out;
}

pub fn withItalic(self: Style, enabled: bool) Style {
    var out = self;
    out.italic = enabled;
    return out;
}

pub fn withUnderline(self: Style, enabled: bool) Style {
    var out = self;
    out.underline = enabled;
    return out;
}

pub fn withDim(self: Style, enabled: bool) Style {
    var out = self;
    out.dim = enabled;
    return out;
}

pub fn withStrikethrough(self: Style, enabled: bool) Style {
    var out = self;
    out.strikethrough = enabled;
    return out;
}

pub fn bolded(self: Style) Style {
    return self.withBold(true);
}

pub fn italicized(self: Style) Style {
    return self.withItalic(true);
}

pub fn underlined(self: Style) Style {
    return self.withUnderline(true);
}

pub fn dimmed(self: Style) Style {
    return self.withDim(true);
}

pub fn striked(self: Style) Style {
    return self.withStrikethrough(true);
}

pub fn render(self: Style, text: []const u8, writer: anytype) !void {
    try self.renderWithProfile(text, writer, profile.colorProfile());
}

pub fn renderWithProfile(self: Style, text: []const u8, writer: anytype, color_profile: ColorProfile) !void {
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

pub fn renderAlloc(self: Style, text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return self.renderAllocWithProfile(text, allocator, profile.colorProfile());
}

pub fn renderAllocWithProfile(self: Style, text: []const u8, allocator: std.mem.Allocator, color_profile: ColorProfile) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var sink = ListSink{
        .list = &out,
        .allocator = allocator,
    };

    try self.renderWithProfile(text, &sink, color_profile);
    return out.toOwnedSlice(allocator);
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
