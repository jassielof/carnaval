const std = @import("std");
const builtin = @import("builtin");

const Utf8Unit = @import("Utf8Unit.zig");
const ansi = @import("ansi.zig");

extern "kernel32" fn SetConsoleOutputCP(code_page: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetConsoleMode(handle: std.os.windows.HANDLE, mode: *std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn GetConsoleScreenBufferInfo(handle: std.os.windows.HANDLE, info: *ConsoleScreenBufferInfo) callconv(.winapi) std.os.windows.BOOL;

const SmallRect = extern struct {
    Left: std.os.windows.SHORT,
    Top: std.os.windows.SHORT,
    Right: std.os.windows.SHORT,
    Bottom: std.os.windows.SHORT,
};

const ConsoleScreenBufferInfo = extern struct {
    dwSize: std.os.windows.COORD,
    dwCursorPosition: std.os.windows.COORD,
    wAttributes: std.os.windows.WORD,
    srWindow: SmallRect,
    dwMaximumWindowSize: std.os.windows.COORD,
};

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

pub fn isTtyHandle(handle: std.Io.File.Handle) bool {
    if (builtin.os.tag == .windows) return isWindowsConsoleHandle(handle);
    return posixTtySize(handle) != null;
}

fn ttyWidth(handle: std.Io.File.Handle) ?usize {
    if (builtin.os.tag == .windows) return windowsTtyWidth(handle);
    return posixTtyWidth(handle);
}

fn posixTtyWidth(handle: std.Io.File.Handle) ?usize {
    const ws = posixTtySize(handle) orelse return null;
    if (ws.col == 0) return null;
    return ws.col;
}

fn posixTtySize(handle: std.Io.File.Handle) ?std.posix.winsize {
    var ws: std.posix.winsize = undefined;
    const rc = std.posix.system.ioctl(handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (std.posix.errno(rc) != .SUCCESS) return null;
    return ws;
}

fn windowsTtyWidth(handle: std.Io.File.Handle) ?usize {
    var csbi: ConsoleScreenBufferInfo = undefined;
    if (!GetConsoleScreenBufferInfo(handle, &csbi).toBool()) return null;

    const width: i32 = csbi.srWindow.Right - csbi.srWindow.Left + 1;
    if (width <= 0) return null;
    return @intCast(width);
}

fn envWidth(name: []const u8) ?usize {
    const value = std.process.Environ.getAlloc(globalEnviron(), std.heap.page_allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableMissing => return null,
        else => return null,
    };
    defer std.heap.page_allocator.free(value);

    return std.fmt.parseInt(usize, value, 10) catch null;
}

fn globalEnviron() std.process.Environ {
    return switch (builtin.os.tag) {
        .windows, .wasi, .emscripten, .freestanding, .other => .{ .block = .global },
        else => .empty,
    };
}

/// Controls word-wrapping behavior for terminal prose.
pub const WrapOptions = struct {
    /// Spaces inserted before continuation lines. It must be smaller than the
    /// requested width so every continuation has room for text.
    indent: usize = 0,
    /// Keep `http://`, `https://`, and similar spans on one line.
    preserve_urls: bool = true,
    /// Keep file paths (`./foo`, `/abs`, `C:\foo`, `~/x`) on one line.
    preserve_paths: bool = true,
    /// Keep backtick-quoted spans on one line.
    preserve_backticks: bool = true,

    /// Defaults tuned for readable help and documentation prose.
    pub const prose: WrapOptions = .{};
};

pub fn wrap(text: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) ![]u8 {
    return wrapWithOptions(text, width, .{ .indent = indent }, allocator);
}

pub fn wrapWithOptions(text: []const u8, width: usize, options: WrapOptions, allocator: std.mem.Allocator) ![]u8 {
    if (width == 0) return allocator.dupe(u8, text);
    if (options.indent >= width) return error.IndentExceedsWidth;

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, text, '\n');
    var first_line = true;
    while (line_it.next()) |line| {
        if (!first_line) try out.append(allocator, '\n');
        first_line = false;

        try wrapSingleLine(&out, line, width, options, allocator);
    }

    return out.toOwnedSlice(allocator);
}

pub fn wrapAnsi(text: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) ![]u8 {
    return wrapAnsiWithOptions(text, width, .{ .indent = indent }, allocator);
}

pub fn wrapAnsiWithOptions(text: []const u8, width: usize, options: WrapOptions, allocator: std.mem.Allocator) ![]u8 {
    if (width == 0) return allocator.dupe(u8, text);
    if (options.indent >= width) return error.IndentExceedsWidth;

    var out = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, text, '\n');
    var first_line = true;
    while (line_it.next()) |line| {
        if (!first_line) try out.append(allocator, '\n');
        first_line = false;

        try wrapSingleLineAnsi(&out, line, width, options, allocator);
    }

    return out.toOwnedSlice(allocator);
}

const WrapToken = struct {
    text: []const u8,
    preserve: bool,
};

fn wrapSingleLine(out: *std.ArrayList(u8), line: []const u8, width: usize, options: WrapOptions, allocator: std.mem.Allocator) !void {
    if (line.len == 0) return;

    var pos: usize = 0;
    var line_display: usize = 0;

    while (nextWrapToken(line, &pos, options)) |token| {
        const word_display = visibleWidthUtf8(token.text);

        if (token.preserve) {
            if (line_display == 0) {
                try out.appendSlice(allocator, token.text);
                line_display = word_display;
                continue;
            }

            if (line_display + 1 + word_display <= width) {
                try out.append(allocator, ' ');
                try out.appendSlice(allocator, token.text);
                line_display += 1 + word_display;
                continue;
            }

            try out.append(allocator, '\n');
            for (0..options.indent) |_| try out.append(allocator, ' ');
            try out.appendSlice(allocator, token.text);
            line_display = word_display;
            continue;
        }

        if (line_display == 0) {
            line_display = try appendWordChunks(out, token.text, width, options.indent, allocator);
            continue;
        }

        if (line_display + 1 + word_display <= width) {
            try out.append(allocator, ' ');
            try out.appendSlice(allocator, token.text);
            line_display += 1 + word_display;
            continue;
        }

        try out.append(allocator, '\n');
        for (0..options.indent) |_| try out.append(allocator, ' ');
        line_display = try appendWordChunks(out, token.text, width, options.indent, allocator);
    }
}

fn appendWordChunks(out: *std.ArrayList(u8), word: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) !usize {
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
            if (started_any) {
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
        if (started_any) {
            try out.append(allocator, '\n');
            for (0..indent) |_| try out.append(allocator, ' ');
        }
        try out.appendSlice(allocator, word[chunk_start..]);
        trailing_display = chunk_display;
    }

    return trailing_display;
}

fn wrapSingleLineAnsi(out: *std.ArrayList(u8), line: []const u8, width: usize, options: WrapOptions, allocator: std.mem.Allocator) !void {
    if (line.len == 0) return;

    var pos: usize = 0;
    var line_visible: usize = 0;

    while (nextWrapToken(line, &pos, options)) |token| {
        const word_visible = ansiDisplayWidth(token.text);

        if (token.preserve) {
            if (line_visible == 0) {
                try out.appendSlice(allocator, token.text);
                line_visible = word_visible;
                continue;
            }

            if (line_visible + 1 + word_visible <= width) {
                try out.append(allocator, ' ');
                try out.appendSlice(allocator, token.text);
                line_visible += 1 + word_visible;
                continue;
            }

            try out.append(allocator, '\n');
            for (0..options.indent) |_| try out.append(allocator, ' ');
            try out.appendSlice(allocator, token.text);
            line_visible = word_visible;
            continue;
        }

        if (line_visible == 0) {
            line_visible = try appendWordChunksAnsi(out, token.text, width, options.indent, allocator);
            continue;
        }

        if (line_visible + 1 + word_visible <= width) {
            try out.append(allocator, ' ');
            try out.appendSlice(allocator, token.text);
            line_visible += 1 + word_visible;
            continue;
        }

        try out.append(allocator, '\n');
        for (0..options.indent) |_| try out.append(allocator, ' ');
        line_visible = try appendWordChunksAnsi(out, token.text, width, options.indent, allocator);
    }
}

fn nextWrapToken(line: []const u8, pos: *usize, options: WrapOptions) ?WrapToken {
    while (pos.* < line.len and (line[pos.*] == ' ' or line[pos.*] == '\t')) pos.* += 1;
    if (pos.* >= line.len) return null;

    const start = pos.*;
    const preserve = scanPreserveToken(line, pos, options) orelse {
        while (pos.* < line.len and line[pos.*] != ' ' and line[pos.*] != '\t') pos.* += 1;
        absorbStickySuffix(line, pos);
        return .{ .text = line[start..pos.*], .preserve = false };
    };
    absorbStickySuffix(line, pos);
    return .{ .text = line[start..pos.*], .preserve = preserve };
}

/// Closing punctuation glued to the prior token (e.g. `` `path`. `` or `https://x.com.`).
fn absorbStickySuffix(line: []const u8, pos: *usize) void {
    while (pos.* < line.len and isStickyClosingChar(line[pos.*])) : (pos.* += 1) {}
}

fn isStickyClosingChar(c: u8) bool {
    return switch (c) {
        '.', ',', ';', ':', '!', '?', ')', ']', '}', '\'', '"' => true,
        else => false,
    };
}

fn scanPreserveToken(line: []const u8, pos: *usize, options: WrapOptions) ?bool {
    const rest = line[pos.*..];
    var control_prefix_len: usize = 0;
    while (true) {
        const sequence_len = ansi.sequenceLen(rest[control_prefix_len..]);
        if (sequence_len == 0) break;
        control_prefix_len += sequence_len;
    }
    const visible_rest = rest[control_prefix_len..];

    if (options.preserve_backticks and visible_rest.len > 0 and visible_rest[0] == '`') {
        if (std.mem.indexOfScalar(u8, visible_rest[1..], '`')) |close_rel| {
            pos.* += control_prefix_len + 2 + close_rel;
            return true;
        }

        return null;
    }

    if (options.preserve_urls) {
        if (urlSpanLen(visible_rest)) |len| {
            pos.* += control_prefix_len + len;
            return true;
        }
    }

    if (options.preserve_paths) {
        if (pathSpanLen(visible_rest)) |len| {
            pos.* += control_prefix_len + len;
            return true;
        }
    }

    return null;
}

fn urlSpanLen(s: []const u8) ?usize {
    const prefixes = [_][]const u8{
        "http://",
        "https://",
        "ftp://",
        "file://",
        "ws://",
        "wss://",
        "mailto:",
    };

    for (prefixes) |prefix|
        if (std.mem.startsWith(u8, s, prefix))
            return trimTrailingPunctuation(s[0..scanUntilWhitespace(s)]);

    if (s.len >= 4 and std.mem.startsWith(u8, s, "www."))
        return trimTrailingPunctuation(s[0..scanUntilWhitespace(s)]);

    return null;
}

fn pathSpanLen(s: []const u8) ?usize {
    if (s.len >= 2 and (std.mem.startsWith(u8, s, "./") or std.mem.startsWith(u8, s, "../"))) {
        return trimTrailingPunctuation(s[0..scanPathChars(s)]);
    }
    if (s.len >= 2 and std.mem.startsWith(u8, s, "~/")) {
        return trimTrailingPunctuation(s[0..scanPathChars(s)]);
    }
    if (s.len >= 2 and s[0] == '/' and !std.ascii.isWhitespace(s[1])) {
        return trimTrailingPunctuation(s[0..scanPathChars(s)]);
    }
    if (s.len >= 3 and std.ascii.isAlphabetic(s[0]) and s[1] == ':' and (s[2] == '/' or s[2] == '\\')) {
        return trimTrailingPunctuation(s[0..scanPathChars(s)]);
    }
    if (s.len >= 2 and s[0] == '\\' and s[1] == '\\') {
        return trimTrailingPunctuation(s[0..scanPathChars(s)]);
    }
    return null;
}

fn scanUntilWhitespace(s: []const u8) usize {
    var i: usize = 0;
    while (i < s.len and !std.ascii.isWhitespace(s[i])) : (i += 1) {}
    return i;
}

fn scanPathChars(s: []const u8) usize {
    var i: usize = 0;
    while (i < s.len and !std.ascii.isWhitespace(s[i])) : (i += 1) {
        const c = s[i];
        if (c == ',' or c == ';' or c == ')' or c == ']' or c == '}') break;
    }
    return i;
}

fn trimTrailingPunctuation(span: []const u8) usize {
    var end = span.len;
    while (end > 0) : (end -= 1) {
        switch (span[end - 1]) {
            '.', ',', ';', ':', '!', '?', ')', ']', '}' => continue,
            else => return end,
        }
    }
    return end;
}

fn appendWordChunksAnsi(out: *std.ArrayList(u8), word: []const u8, width: usize, indent: usize, allocator: std.mem.Allocator) !usize {
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
        const esc_len = ansi.sequenceLen(word[i..]);
        if (esc_len > 0) {
            i += esc_len;
            continue;
        }

        const unit = utf8Unit(word, i);
        if (chunk_visible + unit.display_width > width and chunk_visible > 0) {
            if (started_any) {
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
        if (started_any) {
            try out.append(allocator, '\n');
            for (0..indent) |_| try out.append(allocator, ' ');
        }
        try out.appendSlice(allocator, word[chunk_start..]);
        trailing_visible = chunk_visible;
    }

    return trailing_visible;
}

/// Terminal display width for UTF-8 text while ignoring ANSI escape sequences.
///
/// For multi-line text this returns the width of its widest line, not the sum of
/// every line's widths. This is the horizontal space the text occupies in a terminal.
pub fn ansiDisplayWidth(s: []const u8) usize {
    var i: usize = 0;
    var line_width: usize = 0;
    var max_width: usize = 0;
    while (i < s.len) {
        const esc_len = ansi.sequenceLen(s[i..]);
        if (esc_len > 0) {
            i += esc_len;
            continue;
        }

        const unit = utf8Unit(s, i);
        i += unit.len;
        if (s[i - unit.len] == '\n') {
            max_width = @max(max_width, line_width);
            line_width = 0;
        } else {
            line_width += unit.display_width;
        }
    }
    return @max(max_width, line_width);
}

/// Terminal display width for UTF-8 text.
///
/// For multi-line text this returns the width of its widest line. ANSI sequences
/// are treated as text; use `ansiDisplayWidth` for styled strings.
pub fn utf8DisplayWidth(s: []const u8) usize {
    var i: usize = 0;
    var line_width: usize = 0;
    var max_width: usize = 0;
    while (i < s.len) {
        const unit = utf8Unit(s, i);
        i += unit.len;
        if (s[i - unit.len] == '\n') {
            max_width = @max(max_width, line_width);
            line_width = 0;
        } else {
            line_width += unit.display_width;
        }
    }
    return @max(max_width, line_width);
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

test "wrap preserves urls" {
    const allocator = std.testing.allocator;
    const src = "See https://example.com/docs for details.";
    const wrapped = try wrapWithOptions(src, 24, .{ .indent = 2 }, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings(
        "See\n  https://example.com/docs\n  for details.",
        wrapped,
    );
}

test "wrap preserves paths" {
    const allocator = std.testing.allocator;
    const src = "Edit ./config/docent.toml before running.";
    const wrapped = try wrapWithOptions(src, 20, .{ .indent = 2 }, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings(
        "Edit\n  ./config/docent.toml\n  before running.",
        wrapped,
    );
}

test "wrap preserves backticks" {
    const allocator = std.testing.allocator;
    const src = "Use `--config-path` to override.";
    const wrapped = try wrapWithOptions(src, 16, .{ .indent = 2 }, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings(
        "Use\n  `--config-path`\n  to override.",
        wrapped,
    );
}

test "wrap keeps sentence punctuation attached to backtick spans" {
    const allocator = std.testing.allocator;
    const src = "Search upward for `.config/docent.toml`.";
    const wrapped = try wrapWithOptions(src, 70, .{}, allocator);
    defer allocator.free(wrapped);

    try std.testing.expect(std.mem.indexOf(u8, wrapped, "`.config/docent.toml`.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrapped, "toml` .") == null);
}

test "wrap() keeps sentence punctuation attached to URLs." {
    const allocator = std.testing.allocator;
    const src = "For details, see https://example.com.";
    const wrapped = try wrapWithOptions(src, 70, .{}, allocator);
    defer allocator.free(wrapped);

    try std.testing.expect(std.mem.find(u8, wrapped, "https://example.com.") != null);
    try std.testing.expect(std.mem.find(u8, wrapped, "com .") == null);
}

test "wrap with indent" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("A small sentence for wrapping", 12, 4, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("A small\n    sentence for\n    wrapping", wrapped);
}

test "wrapAnsi ignores sgr sequences when measuring line width" {
    const allocator = std.testing.allocator;
    const src = "\x1b[31mred\x1b[0m \x1b[34mblue\x1b[0m green";
    const wrapped = try wrapAnsi(src, 8, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings(
        "\x1b[31mred\x1b[0m \x1b[34mblue\x1b[0m\n  green",
        wrapped,
    );
}

test "wrap preserves existing line breaks" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("alpha beta\ngamma delta", 8, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("alpha\n  beta\ngamma\n  delta", wrapped);
}

test "wrap chunks a long utf8 word by display width" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("你好世界", 4, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("你好\n  世界", wrapped);
}

test "wrap does not insert an empty line before a long continuation word" {
    const allocator = std.testing.allocator;
    const wrapped = try wrap("go abcdef", 3, 1, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("go\n abc\n def", wrapped);
}

test "wrap rejects an indent that leaves no room for continuation text" {
    try std.testing.expectError(
        error.IndentExceedsWidth,
        wrap("alpha beta", 2, 2, std.testing.allocator),
    );
}

test "ansi display width ignores OSC 8 hyperlinks" {
    const link = "\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\";
    try std.testing.expectEqual(@as(usize, 4), ansiDisplayWidth(link));
}

test "wrapAnsi preserves a URL prefixed by ANSI styling" {
    const allocator = std.testing.allocator;
    const src = "See \x1b[34mhttps://example.com/docs\x1b[0m now";
    const wrapped = try wrapAnsi(src, 12, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings(
        "See\n  \x1b[34mhttps://example.com/docs\x1b[0m\n  now",
        wrapped,
    );
}

test "utf8DisplayWidth counts wide and combining codepoints" {
    try std.testing.expectEqual(@as(usize, 6), utf8DisplayWidth("a你好e\u{0301}"));
}

test "wrapWithOptions prose defaults preserve urls and paths" {
    const allocator = std.testing.allocator;
    const src = "Read https://ziglang.org and edit ./build.zig next.";
    const wrapped = try wrapWithOptions(src, 22, WrapOptions.prose, allocator);
    defer allocator.free(wrapped);

    try std.testing.expect(std.mem.indexOf(u8, wrapped, "https://ziglang.org") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrapped, "./build.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrapped, "https://zig\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, wrapped, "./build.\n") == null);
}
