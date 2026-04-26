const std = @import("std");
const carnaval = @import("carnaval");

const allocator = std.testing.allocator;

test "wrapAnsi ignores sgr sequences when measuring line width" {
    const src = "\x1b[31mred\x1b[0m \x1b[34mblue\x1b[0m green";
    const wrapped = try carnaval.wrapAnsi(src, 8, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings(
        "\x1b[31mred\x1b[0m \x1b[34mblue\x1b[0m\n  green",
        wrapped,
    );
}

test "wrap preserves existing line breaks" {
    const wrapped = try carnaval.wrap("alpha beta\ngamma delta", 8, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("alpha\n  beta\ngamma\n  delta", wrapped);
}

test "wrap chunks a long utf8 word by display width" {
    const wrapped = try carnaval.wrap("你好世界", 4, 2, allocator);
    defer allocator.free(wrapped);

    try std.testing.expectEqualStrings("你好\n  世界", wrapped);
}

test "utf8DisplayWidth counts wide and combining codepoints" {
    try std.testing.expectEqual(@as(usize, 6), carnaval.utf8DisplayWidth("a你好e\u{0301}"));
}
