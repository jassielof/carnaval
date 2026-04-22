const std = @import("std");

const carnaval = @import("carnaval");

test "integration: wrap with indent" {
    const allocator = std.testing.allocator;
    const wrapped = try carnaval.wrap("A small sentence for wrapping", 12, 4, allocator);

    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("A small\n    sentence for\n    wrapping", wrapped);
}

test "integration: style render uses reset" {
    const allocator = std.testing.allocator;
    const st = carnaval.Style.init()
        .fg(.{ .ansi16 = .green })
        .withUnderline(true);

    const rendered = try st.renderAllocWithProfile("ok", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.endsWith(u8, rendered, "\x1b[0m"));
}
