const std = @import("std");
const builtin = @import("builtin");
const term = @import("term.zig");

pub const ColorProfile = enum {
    none,
    ansi16,
    ansi256,
    true_color,
};

pub fn colorProfile() ColorProfile {
    return colorProfileForHandle(std.fs.File.stdout().handle);
}

pub fn colorProfileForHandle(handle: std.fs.File.Handle) ColorProfile {
    term.prepareWindowsConsoleIfNeeded(handle);

    if (hasEnv("NO_COLOR")) return .none;
    if (!isTtyHandle(handle)) return .none;

    if (envValue("TERM")) |v| {
        defer std.heap.page_allocator.free(v);
        if (std.mem.eql(u8, v, "dumb")) return .none;
    }

    const colorterm = envValue("COLORTERM");
    if (colorterm) |v| {
        defer std.heap.page_allocator.free(v);
        if (std.ascii.indexOfIgnoreCase(v, "truecolor") != null) return .true_color;
        if (std.ascii.indexOfIgnoreCase(v, "24bit") != null) return .true_color;
    }

    if (envValue("TERM")) |v| {
        defer std.heap.page_allocator.free(v);
        if (std.mem.indexOf(u8, v, "256color") != null) return .ansi256;
    }

    if (builtin.os.tag == .windows) return .true_color;
    return .ansi16;
}

fn hasEnv(name: []const u8) bool {
    const value = envValue(name) orelse return false;
    std.heap.page_allocator.free(value);
    return true;
}

fn envValue(name: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => null,
    };
}

fn isTtyHandle(handle: std.fs.File.Handle) bool {
    if (builtin.os.tag == .windows) return term.isWindowsConsoleHandle(handle);
    return std.posix.isatty(handle);
}
