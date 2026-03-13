const std = @import("std");
const builtin = @import("builtin");

pub fn terminalWidth() usize {
    return terminalWidthForHandle(std.io.getStdOut().handle);
}

pub fn terminalWidthForHandle(handle: std.fs.File.Handle) usize {
    if (ttyWidth(handle)) |w| {
        if (w > 0) return w;
    }

    if (envWidth("COLUMNS")) |w| {
        if (w > 0) return w;
    }

    return 80;
}

fn ttyWidth(handle: std.fs.File.Handle) ?usize {
    if (builtin.os.tag == .windows) return windowsTtyWidth(handle);
    return posixTtyWidth(handle);
}

fn posixTtyWidth(handle: std.fs.File.Handle) ?usize {
    if (!std.posix.isatty(handle)) return null;

    var ws: std.posix.winsize = undefined;
    const rc = std.posix.system.ioctl(handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(rc) != .SUCCESS) return null;
    if (ws.col == 0) return null;
    return ws.col;
}

fn windowsTtyWidth(handle: std.fs.File.Handle) ?usize {
    var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(handle, &csbi) == 0) return null;

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

pub fn wrapAnsi(text: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) ![]u8 {
    if (width == 0) return allocator.dupe(u8, text);

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, text, '\n');
    var first_line = true;
    while (line_it.next()) |line| {
        if (!first_line) try out.append(allocator, '\n');
        first_line = false;

        try wrapSingleLineAnsi(&out, line, width, indent, allocator);
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

fn wrapSingleLineAnsi(out: *std.ArrayList(u8), line: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) !void {
    if (line.len == 0) return;

    var word_it = std.mem.tokenizeAny(u8, line, " \t");
    var line_visible: usize = 0;

    while (word_it.next()) |word| {
        const word_visible = visibleWidth(word);

        if (line_visible == 0) {
            try appendWordChunksAnsi(out, word, width, indent, false, allocator);
            line_visible = @min(word_visible, width);
            continue;
        }

        if (line_visible + 1 + word_visible <= width) {
            try out.append(allocator, ' ');
            try out.appendSlice(allocator, word);
            line_visible += 1 + word_visible;
            continue;
        }

        try out.append(allocator, '\n');
        for (0..indent) |_| try out.append(allocator, ' ');
        try appendWordChunksAnsi(out, word, width, indent, true, allocator);
        line_visible = @min(word_visible, width);
    }
}

fn appendWordChunksAnsi(out: *std.ArrayList(u8), word: []const u8, width: usize, indent: usize, continuation: bool, allocator: std.mem.Allocator) !void {
    if (visibleWidth(word) <= width) {
        try out.appendSlice(allocator, word);
        return;
    }

    var i: usize = 0;
    var chunk_start: usize = 0;
    var chunk_visible: usize = 0;
    var started_any = false;

    while (i < word.len) {
        const esc_len = ansiSeqLen(word[i..]);
        if (esc_len > 0) {
            i += esc_len;
            continue;
        }

        if (chunk_visible == width) {
            if (started_any or continuation) {
                try out.append(allocator, '\n');
                for (0..indent) |_| try out.append(allocator, ' ');
            }
            try out.appendSlice(allocator, word[chunk_start..i]);
            chunk_start = i;
            chunk_visible = 0;
            started_any = true;
            continue;
        }

        i += 1;
        chunk_visible += 1;
    }

    if (chunk_start < word.len) {
        if (started_any or continuation) {
            try out.append(allocator, '\n');
            for (0..indent) |_| try out.append(allocator, ' ');
        }
        try out.appendSlice(allocator, word[chunk_start..]);
    }
}

fn visibleWidth(s: []const u8) usize {
    var i: usize = 0;
    var visible: usize = 0;
    while (i < s.len) {
        const esc_len = ansiSeqLen(s[i..]);
        if (esc_len > 0) {
            i += esc_len;
            continue;
        }
        i += 1;
        visible += 1;
    }
    return visible;
}

fn ansiSeqLen(s: []const u8) usize {
    if (s.len < 2) return 0;
    if (s[0] != 0x1b or s[1] != '[') return 0;

    var i: usize = 2;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (ch >= 0x40 and ch <= 0x7e) return i + 1;
    }
    return 0;
}

test "wrap simple paragraph" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("alpha beta gamma delta", 10, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("alpha beta\n  gamma\n  delta", wrapped);
}

test "wrap ansi paragraph" {
    const allocator = std.testing.allocator;
    const src = "\x1b[31malpha beta gamma\x1b[0m";
    const wrapped = try wrapAnsi(src, 10, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("\x1b[31malpha beta\n  gamma\x1b[0m", wrapped);
}
