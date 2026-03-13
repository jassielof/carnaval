const std = @import("std");
const builtin = @import("builtin");
const profile = @import("profile.zig");

pub fn terminalWidth() usize {
    if (profile.colorProfile() != .none) {
        if (ttyWidth()) |w| {
            if (w > 0) return w;
        }
    }

    if (envWidth("COLUMNS")) |w| {
        if (w > 0) return w;
    }

    return 80;
}

fn ttyWidth() ?usize {
    if (builtin.os.tag == .windows) return windowsTtyWidth();
    return posixTtyWidth();
}

fn posixTtyWidth() ?usize {
    const stdout_file = std.io.getStdOut();
    if (!std.posix.isatty(stdout_file.handle)) return null;

    var ws: std.posix.winsize = undefined;
    const rc = std.posix.system.ioctl(stdout_file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(rc) != .SUCCESS) return null;
    if (ws.col == 0) return null;
    return ws.col;
}

fn windowsTtyWidth() ?usize {
    const stdout_file = std.io.getStdOut();
    var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(stdout_file.handle, &csbi) == 0) return null;

    const width: i32 = csbi.srWindow.Right - csbi.srWindow.Left + 1;
    if (width <= 0) return null;
    return @intCast(width);
}

fn envWidth(name: []const u8) ?usize {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return null,
    };
    defer std.heap.page_allocator.free(value);

    return std.fmt.parseInt(usize, value, 10) catch null;
}

pub fn wrap(text: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) ![]u8 {
    if (width == 0) return allocator.dupe(u8, text);

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, text, '\n');
    var first_line = true;
    while (line_it.next()) |line| {
        if (!first_line) try out.append(allocator, '\n');
        first_line = false;

        try wrapSingleLine(&out, line, width, indent, allocator);
    }

    return out.toOwnedSlice(allocator);
}

fn wrapSingleLine(out: *std.ArrayList(u8), line: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) !void {
    if (line.len == 0) return;

    var word_it = std.mem.tokenizeAny(u8, line, " \t");
    var line_len: usize = 0;

    while (word_it.next()) |word| {
        if (line_len == 0) {
            try appendWordChunks(out, word, width, indent, false, allocator);
            line_len = @min(word.len, width);
            continue;
        }

        if (line_len + 1 + word.len <= width) {
            try out.append(allocator, ' ');
            try out.appendSlice(allocator, word);
            line_len += 1 + word.len;
            continue;
        }

        try out.append(allocator, '\n');
        for (0..indent) |_| try out.append(allocator, ' ');
        try appendWordChunks(out, word, width, indent, true, allocator);
        line_len = @min(word.len, width);
    }
}

fn appendWordChunks(out: *std.ArrayList(u8), word: []const u8, width: usize, indent: usize, continuation: bool, allocator: std.mem.Allocator) !void {

    if (word.len <= width) {
        try out.appendSlice(allocator, word);
        return;
    }

    var start: usize = 0;
    var first = true;
    while (start < word.len) {
        if (!first or continuation) {
            try out.append(allocator, '\n');
            for (0..indent) |_| try out.append(allocator, ' ');
        }

        const remaining = word.len - start;
        const take = @min(remaining, width);
        try out.appendSlice(allocator, word[start .. start + take]);
        start += take;
        first = false;
    }
}

test "wrap simple paragraph" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("alpha beta gamma delta", 10, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("alpha beta\n  gamma\n  delta", wrapped);
}
