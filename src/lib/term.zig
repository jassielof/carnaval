const std = @import("std");
const builtin = @import("builtin");

const Utf8Unit = @import("Utf8Unit.zig");

extern "kernel32" fn SetConsoleOutputCP(code_page: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetConsoleMode(handle: std.os.windows.HANDLE, mode: *std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL;

var windows_console_utf8_mutex: std.atomic.Mutex = .unlocked;
var windows_console_utf8_done: bool = false;

/// `true` when `handle` is a Windows console device (as opposed to a pipe or file).
pub fn isWindowsConsoleHandle(handle: std.Io.File.Handle) bool {
    if (builtin.os.tag != .windows) return false;

    var mode: std.os.windows.DWORD = 0;
    return GetConsoleMode(handle, &mode).toBool();
}

/// If `handle` is a Windows console, selects UTF-8 (code page 65001) once per process so UTF-8 output decodes correctly. No-op on other OSes or non-console handles.
///
/// Called automatically from `terminalWidthForHandle`, `colorProfileForHandle`, and Unicode table rendering. Go / Lip Gloss do not need an equivalent: the Go runtime uses different Windows console integration; Zig writes UTF-8 bytes and must set the console code page (or use wide APIs) for correct display.
pub fn prepareWindowsConsoleIfNeeded(handle: std.Io.File.Handle) void {
    if (builtin.os.tag != .windows) return;
    if (!isWindowsConsoleHandle(handle)) return;

    while (!windows_console_utf8_mutex.tryLock()) {}
    defer windows_console_utf8_mutex.unlock();
    if (windows_console_utf8_done) return;
    windows_console_utf8_done = true;

    const CP_UTF8: std.os.windows.UINT = 65001;
    _ = SetConsoleOutputCP(CP_UTF8);
}

pub fn terminalWidth() usize {
    return terminalWidthForHandle(std.Io.File.stdout().handle);
}

pub fn terminalWidthForHandle(handle: std.Io.File.Handle) usize {
    prepareWindowsConsoleIfNeeded(handle);

    if (ttyWidth(handle)) |w| {
        if (w > 0) return w;
    }

    if (envWidth("COLUMNS")) |w| {
        if (w > 0) return w;
    }

    return 80;
}

fn ttyWidth(handle: std.Io.File.Handle) ?usize {
    if (builtin.os.tag == .windows) return windowsTtyWidth(handle);
    return posixTtyWidth(handle);
}

fn posixTtyWidth(handle: std.Io.File.Handle) ?usize {
    if (!std.posix.isatty(handle)) return null;

    var ws: std.posix.winsize = undefined;
    const rc = std.posix.system.ioctl(handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(rc) != .SUCCESS) return null;
    if (ws.col == 0) return null;
    return ws.col;
}

fn windowsTtyWidth(handle: std.Io.File.Handle) ?usize {
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
    var line_display: usize = 0;

    while (word_it.next()) |word| {
        const word_display = visibleWidthUtf8(word);

        if (line_display == 0) {
            line_display = try appendWordChunks(out, word, width, indent, false, allocator);
            continue;
        }

        if (line_display + 1 + word_display <= width) {
            try out.append(allocator, ' ');
            try out.appendSlice(allocator, word);
            line_display += 1 + word_display;
            continue;
        }

        try out.append(allocator, '\n');
        for (0..indent) |_| try out.append(allocator, ' ');
        line_display = try appendWordChunks(out, word, width, indent, true, allocator);
    }
}

fn appendWordChunks(out: *std.ArrayList(u8), word: []const u8, width: usize, indent: usize, continuation: bool, allocator: std.mem.Allocator) !usize {
    const word_display = visibleWidthUtf8(word);
    if (word_display <= width) {
        try out.appendSlice(allocator, word);
        return word_display;
    }

    var i: usize = 0;
    var chunk_start: usize = 0;
    var chunk_display: usize = 0;
    var started_any = false;
    var trailing_display: usize = 0;

    while (i < word.len) {
        const unit = utf8Unit(word, i);
        if (chunk_display + unit.display_width > width and chunk_display > 0) {
            if (started_any or continuation) {
                try out.append(allocator, '\n');
                for (0..indent) |_| try out.append(allocator, ' ');
            }
            try out.appendSlice(allocator, word[chunk_start..i]);
            trailing_display = chunk_display;
            chunk_start = i;
            chunk_display = 0;
            started_any = true;
            continue;
        }

        i += unit.len;
        chunk_display += unit.display_width;
    }

    if (chunk_start < word.len) {
        if (started_any or continuation) {
            try out.append(allocator, '\n');
            for (0..indent) |_| try out.append(allocator, ' ');
        }
        try out.appendSlice(allocator, word[chunk_start..]);
        trailing_display = chunk_display;
    }

    return trailing_display;
}

fn wrapSingleLineAnsi(out: *std.ArrayList(u8), line: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) !void {
    if (line.len == 0) return;

    var word_it = std.mem.tokenizeAny(u8, line, " \t");
    var line_visible: usize = 0;

    while (word_it.next()) |word| {
        const word_visible = ansiDisplayWidth(word);

        if (line_visible == 0) {
            line_visible = try appendWordChunksAnsi(out, word, width, indent, false, allocator);
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
        line_visible = try appendWordChunksAnsi(out, word, width, indent, true, allocator);
    }
}

fn appendWordChunksAnsi(out: *std.ArrayList(u8), word: []const u8, width: usize, indent: usize, continuation: bool, allocator: std.mem.Allocator) !usize {
    if (ansiDisplayWidth(word) <= width) {
        try out.appendSlice(allocator, word);
        return ansiDisplayWidth(word);
    }

    var i: usize = 0;
    var chunk_start: usize = 0;
    var chunk_visible: usize = 0;
    var started_any = false;
    var trailing_visible: usize = 0;

    while (i < word.len) {
        const esc_len = ansiSeqLen(word[i..]);
        if (esc_len > 0) {
            i += esc_len;
            continue;
        }

        const unit = utf8Unit(word, i);
        if (chunk_visible + unit.display_width > width and chunk_visible > 0) {
            if (started_any or continuation) {
                try out.append(allocator, '\n');
                for (0..indent) |_| try out.append(allocator, ' ');
            }
            try out.appendSlice(allocator, word[chunk_start..i]);
            trailing_visible = chunk_visible;
            chunk_start = i;
            chunk_visible = 0;
            started_any = true;
            continue;
        }

        i += unit.len;
        chunk_visible += unit.display_width;
    }

    if (chunk_start < word.len) {
        if (started_any or continuation) {
            try out.append(allocator, '\n');
            for (0..indent) |_| try out.append(allocator, ' ');
        }
        try out.appendSlice(allocator, word[chunk_start..]);
        trailing_visible = chunk_visible;
    }

    return trailing_visible;
}

/// Terminal display width for UTF-8 text while ignoring ANSI CSI escape sequences.
pub fn ansiDisplayWidth(s: []const u8) usize {
    var i: usize = 0;
    var visible: usize = 0;
    while (i < s.len) {
        const esc_len = ansiSeqLen(s[i..]);
        if (esc_len > 0) {
            i += esc_len;
            continue;
        }

        const unit = utf8Unit(s, i);
        i += unit.len;
        visible += unit.display_width;
    }
    return visible;
}

/// Terminal display width for UTF-8 text (excludes ANSI sequences; use `wrapAnsi` helpers for styled strings).
pub fn utf8DisplayWidth(s: []const u8) usize {
    return visibleWidthUtf8(s);
}

test utf8DisplayWidth {
    try std.testing.expectEqual(@as(usize, 6), utf8DisplayWidth("a你好e\u{0301}"));
}

test ansiDisplayWidth {
    try std.testing.expectEqual(@as(usize, 5), ansiDisplayWidth("\x1b[31mred\x1b[0m好"));
}

fn visibleWidthUtf8(s: []const u8) usize {
    var i: usize = 0;
    var visible: usize = 0;
    while (i < s.len) {
        const unit = utf8Unit(s, i);
        i += unit.len;
        visible += unit.display_width;
    }
    return visible;
}

fn utf8Unit(s: []const u8, index: usize) Utf8Unit {
    const first = s[index];
    const seq_len = std.unicode.utf8ByteSequenceLength(first) catch {
        return .{ .len = 1, .display_width = 1 };
    };
    const len: usize = seq_len;
    if (index + len > s.len) return .{ .len = 1, .display_width = 1 };

    if (len == 1) {
        return .{ .len = 1, .display_width = codepointWidth(first) };
    }

    const cp = std.unicode.utf8Decode(s[index .. index + len]) catch {
        return .{ .len = 1, .display_width = 1 };
    };
    return .{ .len = len, .display_width = codepointWidth(cp) };
}

fn codepointWidth(cp: u21) usize {
    if (cp == 0) return 0;
    if (cp < 32 or (cp >= 0x7f and cp < 0xa0)) return 0;
    if (cp == 0x200d) return 0;
    if (inRange(cp, 0x0300, 0x036f) or
        inRange(cp, 0x1ab0, 0x1aff) or
        inRange(cp, 0x1dc0, 0x1dff) or
        inRange(cp, 0x20d0, 0x20ff) or
        inRange(cp, 0xfe20, 0xfe2f) or
        inRange(cp, 0xfe00, 0xfe0f) or
        inRange(cp, 0xe0100, 0xe01ef))
    {
        return 0;
    }

    if (isWideCodepoint(cp)) return 2;
    return 1;
}

fn isWideCodepoint(cp: u21) bool {
    return inRange(cp, 0x1100, 0x115f) or
        inRange(cp, 0x2329, 0x232a) or
        inRange(cp, 0x2e80, 0xa4cf) or
        inRange(cp, 0xac00, 0xd7a3) or
        inRange(cp, 0xf900, 0xfaff) or
        inRange(cp, 0xfe10, 0xfe19) or
        inRange(cp, 0xfe30, 0xfe6f) or
        inRange(cp, 0xff00, 0xff60) or
        inRange(cp, 0xffe0, 0xffe6) or
        inRange(cp, 0x1f300, 0x1f64f) or
        inRange(cp, 0x1f680, 0x1f6ff) or
        inRange(cp, 0x1f900, 0x1f9ff) or
        inRange(cp, 0x20000, 0x3fffd);
}

fn inRange(cp: u21, lo: u21, hi: u21) bool {
    return cp >= lo and cp <= hi;
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

test "wrap ansi with multiple sgr sequences" {
    const allocator = std.testing.allocator;
    const src = "\x1b[31mred\x1b[0m \x1b[34mblue\x1b[0m green";
    const wrapped = try wrapAnsi(src, 8, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("\x1b[31mred\x1b[0m \x1b[34mblue\x1b[0m\n  green", wrapped);
}

test "wrap utf8 cjk display width" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("你好世界 hello", 6, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("你好世\n  界\n  hello", wrapped);
}

test "wrap utf8 combining marks" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("e\u{0301}e\u{0301} e\u{0301}", 3, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("e\u{0301}e\u{0301}\n  e\u{0301}", wrapped);
}

test "wrap ansi utf8 display width" {
    const allocator = std.testing.allocator;
    const src = "\x1b[31m你好世界\x1b[0m ok";
    const wrapped = try wrapAnsi(src, 6, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("\x1b[31m你好世\n  界\x1b[0m ok", wrapped);
}
