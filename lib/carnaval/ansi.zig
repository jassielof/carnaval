//! ANSI escape-sequence recognition used by Carnaval's text utilities.
//!
//! This module deliberately recognizes control sequences without interpreting
//! their meaning. That keeps measurement and layout independent from terminal
//! capability detection while correctly treating common CSI and OSC sequences
//! (including OSC 8 hyperlinks) as zero-width.

/// Returns the byte length of the ANSI escape sequence beginning at `bytes`,
/// or zero when `bytes` does not begin with a complete recognized sequence.
pub fn sequenceLen(bytes: []const u8) usize {
    if (bytes.len < 2 or bytes[0] != 0x1b) return 0;

    return switch (bytes[1]) {
        '[' => csiLen(bytes),
        ']', 'P', '^', '_' => stringControlLen(bytes),
        else => if (bytes[1] >= 0x30 and bytes[1] <= 0x7e) 2 else 0,
    };
}

fn csiLen(bytes: []const u8) usize {
    var i: usize = 2;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] >= 0x40 and bytes[i] <= 0x7e) return i + 1;
    }
    return 0;
}

/// OSC, DCS, PM, and APC are terminated by BEL or the ST sequence (ESC \\).
fn stringControlLen(bytes: []const u8) usize {
    var i: usize = 2;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == 0x07) return i + 1;
        if (bytes[i] == 0x1b and i + 1 < bytes.len and bytes[i + 1] == '\\') return i + 2;
    }
    return 0;
}

test "recognizes CSI and OSC sequences" {
    try @import("std").testing.expectEqual(@as(usize, 5), sequenceLen("\x1b[31mtext"));
    try @import("std").testing.expectEqual(@as(usize, 26), sequenceLen("\x1b]8;;https://example.com\x1b\\link"));
}

test "does not consume incomplete sequences" {
    try @import("std").testing.expectEqual(@as(usize, 0), sequenceLen("\x1b[31"));
    try @import("std").testing.expectEqual(@as(usize, 0), sequenceLen("\x1b]8;;https://example.com"));
}
