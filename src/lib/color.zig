const std = @import("std");

const ColorProfile = @import("profile.zig").ColorProfile;
const escape = @import("escape.zig");
pub const Rgb = @import("RgbColor.zig");





pub const Ansi16 = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};



pub const Color = union(enum) {
    none,
    ansi16: Ansi16,
    ansi256: u8,
    true_color: Rgb,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .true_color = .{ .r = r, .g = g, .b = b } };
    }

    pub fn emitFg(self: Color, writer: anytype, profile: ColorProfile) !bool {
        if (profile == .none) return false;
        return switch (self.downsample(profile)) {
            .none => false,
            .ansi16 => |v| blk: {
                const n = @intFromEnum(v);
                const code: u8 = if (n < 8) 30 + n else 90 + (n - 8);
                var buf: [12]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "{s}{d}m", .{ escape.csi, code });
                try writer.writeAll(seq);
                break :blk true;
            },
            .ansi256 => |v| blk: {
                var buf: [20]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "{s}38;5;{d}m", .{ escape.csi, v });
                try writer.writeAll(seq);
                break :blk true;
            },
            .true_color => |rgb_color| blk: {
                var buf: [32]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "{s}38;2;{d};{d};{d}m", .{ escape.csi, rgb_color.r, rgb_color.g, rgb_color.b });
                try writer.writeAll(seq);
                break :blk true;
            },
        };
    }

    pub fn emitBg(self: Color, writer: anytype, profile: ColorProfile) !bool {
        if (profile == .none) return false;
        return switch (self.downsample(profile)) {
            .none => false,
            .ansi16 => |v| blk: {
                const n = @intFromEnum(v);
                const code: u8 = if (n < 8) 40 + n else 100 + (n - 8);
                var buf: [12]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "{s}{d}m", .{ escape.csi, code });
                try writer.writeAll(seq);
                break :blk true;
            },
            .ansi256 => |v| blk: {
                var buf: [20]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "{s}48;5;{d}m", .{ escape.csi, v });
                try writer.writeAll(seq);
                break :blk true;
            },
            .true_color => |rgb_color| blk: {
                var buf: [32]u8 = undefined;
                const seq = try std.fmt.bufPrint(&buf, "{s}48;2;{d};{d};{d}m", .{ escape.csi, rgb_color.r, rgb_color.g, rgb_color.b });
                try writer.writeAll(seq);
                break :blk true;
            },
        };
    }

    pub fn downsample(self: Color, profile: ColorProfile) Color {
        return switch (profile) {
            .none => .none,
            .true_color => self,
            .ansi256 => switch (self) {
                .none => .none,
                .ansi16 => |v| .{ .ansi256 = ansi16ToAnsi256(v) },
                .ansi256 => self,
                .true_color => |rgb_color| .{ .ansi256 = rgbToAnsi256(rgb_color) },
            },
            .ansi16 => switch (self) {
                .none => .none,
                .ansi16 => self,
                .ansi256 => |v| .{ .ansi16 = ansi256ToAnsi16(v) },
                .true_color => |rgb_color| .{ .ansi16 = rgbToAnsi16(rgb_color) },
            },
        };
    }
};

fn ansi16ToAnsi256(v: Ansi16) u8 {
    return @intFromEnum(v);
}

fn rgbToAnsi256(rgb: Rgb) u8 {
    if (rgb.r == rgb.g and rgb.g == rgb.b) {
        if (rgb.r < 8) return 16;
        if (rgb.r > 248) return 231;
        const offset: u16 = @intCast(rgb.r - 8);
        const step: u8 = @intCast((offset * 24) / 247);
        return 232 + step;
    }

    const r: u8 = @intCast((@as(u16, rgb.r) * 5 + 127) / 255);
    const g: u8 = @intCast((@as(u16, rgb.g) * 5 + 127) / 255);
    const b: u8 = @intCast((@as(u16, rgb.b) * 5 + 127) / 255);
    return 16 + 36 * r + 6 * g + b;
}

fn ansi256ToRgb(v: u8) Rgb {
    if (v < 16) {
        return switch (v) {
            0 => .{ .r = 0, .g = 0, .b = 0 },
            1 => .{ .r = 128, .g = 0, .b = 0 },
            2 => .{ .r = 0, .g = 128, .b = 0 },
            3 => .{ .r = 128, .g = 128, .b = 0 },
            4 => .{ .r = 0, .g = 0, .b = 128 },
            5 => .{ .r = 128, .g = 0, .b = 128 },
            6 => .{ .r = 0, .g = 128, .b = 128 },
            7 => .{ .r = 192, .g = 192, .b = 192 },
            8 => .{ .r = 128, .g = 128, .b = 128 },
            9 => .{ .r = 255, .g = 0, .b = 0 },
            10 => .{ .r = 0, .g = 255, .b = 0 },
            11 => .{ .r = 255, .g = 255, .b = 0 },
            12 => .{ .r = 0, .g = 0, .b = 255 },
            13 => .{ .r = 255, .g = 0, .b = 255 },
            14 => .{ .r = 0, .g = 255, .b = 255 },
            else => .{ .r = 255, .g = 255, .b = 255 },
        };
    }

    if (v >= 232) {
        const c: u8 = 8 + (v - 232) * 10;
        return .{ .r = c, .g = c, .b = c };
    }

    const n = v - 16;
    const r_idx = n / 36;
    const g_idx = (n % 36) / 6;
    const b_idx = n % 6;
    const cube = [_]u8{ 0, 95, 135, 175, 215, 255 };
    return .{ .r = cube[r_idx], .g = cube[g_idx], .b = cube[b_idx] };
}

fn rgbToAnsi16(rgb: Rgb) Ansi16 {
    const max = @max(rgb.r, @max(rgb.g, rgb.b));
    const min = @min(rgb.r, @min(rgb.g, rgb.b));
    const bright = max >= 180;

    if (max < 40) return if (bright) .bright_black else .black;
    if (max - min < 24) {
        if (bright) return .bright_white;
        if (max < 96) return .bright_black;
        return .white;
    }

    const r_hi = rgb.r >= 128;
    const g_hi = rgb.g >= 128;
    const b_hi = rgb.b >= 128;
    const code: u8 = @as(u8, @intFromBool(r_hi)) | (@as(u8, @intFromBool(g_hi)) << 1) | (@as(u8, @intFromBool(b_hi)) << 2);
    const base: u8 = if (bright and code != 0) 8 else 0;
    return @enumFromInt(base + code);
}

fn ansi256ToAnsi16(v: u8) Ansi16 {
    if (v < 16) return @enumFromInt(v);
    return rgbToAnsi16(ansi256ToRgb(v));
}

test "downsample true color to ansi256" {
    const c = Color.rgb(255, 0, 0).downsample(.ansi256);
    try std.testing.expect(c == .ansi256);
}

test "downsample true color red maps to ansi256 196" {
    const c = Color.rgb(255, 0, 0).downsample(.ansi256);
    try std.testing.expectEqualDeep(Color{ .ansi256 = 196 }, c);
}

test "downsample true color red maps to ansi16 bright_red" {
    const c = Color.rgb(255, 0, 0).downsample(.ansi16);
    try std.testing.expectEqualDeep(Color{ .ansi16 = .bright_red }, c);
}

test "downsample ansi256 196 maps to ansi16 bright_red" {
    const c = (Color{ .ansi256 = 196 }).downsample(.ansi16);
    try std.testing.expectEqualDeep(Color{ .ansi16 = .bright_red }, c);
}
