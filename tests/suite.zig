const std = @import("std");
const allocator = std.testing.allocator;

const carnaval = @import("carnaval");

comptime {
    _ = @import("style_rendering.zig");
    _ = @import("table_rendering.zig");
    _ = @import("wrapping.zig");
}

test "wrap with indent" {
    const wrapped = try carnaval.wrap("A small sentence for wrapping", 12, 4, allocator);

    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("A small\n    sentence for\n    wrapping", wrapped);
}

test "style render uses reset" {
    const st = carnaval.Style.init()
        .fg(.{ .ansi16 = .green })
        .withUnderline(true);

    const rendered = try st.renderAllocWithProfile("ok", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.endsWith(u8, rendered, "\x1b[0m"));
}
