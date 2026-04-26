const std = @import("std");
const carnaval = @import("carnaval");

const allocator = std.testing.allocator;

test "list renders exact bullet output" {
    const rendered = try carnaval.renderListAlloc(allocator, &.{ "Glitter", "Masks", "Drums" }, .{});
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("• Glitter\n• Masks\n• Drums", rendered);
}

test "list renders exact alphabet output across rollover" {
    const rendered = try carnaval.renderListAlloc(
        allocator,
        &.{
            "a", "b", "c", "d", "e", "f", "g", "h", "i",
            "j", "k", "l", "m", "n", "o", "p", "q", "r",
            "s", "t", "u", "v", "w", "x", "y", "z", "aa",
        },
        .{ .style = .alphabet },
    );
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, " A. a") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, " Z. z") != null);
    try std.testing.expect(std.mem.endsWith(u8, rendered, "AA. aa"));
}

test "list renders exact roman output and alignment" {
    const rendered = try carnaval.renderListAlloc(
        allocator,
        &.{ "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" },
        .{ .style = .roman },
    );
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "   I. one\n" ++
            "  II. two\n" ++
            " III. three\n" ++
            "  IV. four\n" ++
            "   V. five\n" ++
            "  VI. six\n" ++
            " VII. seven\n" ++
            "VIII. eight\n" ++
            "  IX. nine\n" ++
            "   X. ten",
        rendered,
    );
}

test "list renders multiline continuation under item text" {
    const rendered = try carnaval.renderListAlloc(
        allocator,
        &.{ "short", "first line\nsecond line\nthird line" },
        .{ .style = .arabic },
    );
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "1. short\n" ++
            "2. first line\n" ++
            "   second line\n" ++
            "   third line",
        rendered,
    );
}

test "list renders styled marker and item output" {
    const rendered = try carnaval.renderListAlloc(allocator, &.{"ok"}, .{
        .style = .dash,
        .marker_style = carnaval.Style.init().fg(.{ .ansi16 = .green }),
        .item_style = carnaval.Style.init().bolded(),
        .color_profile = .ansi16,
    });
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("\x1b[32m-\x1b[0m \x1b[1mok\x1b[0m", rendered);
}

test "list renders nested items" {
    const items = [_]carnaval.ListItem{
        carnaval.ListItem.withChildren("prepare", &.{
            carnaval.ListItem.init("mask"),
            carnaval.ListItem.init("drums"),
        }),
        carnaval.ListItem.init("parade"),
    };

    const rendered = try carnaval.renderListItemsAlloc(allocator, &items, .{ .style = .dash });
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "- prepare\n" ++
            "  - mask\n" ++
            "  - drums\n" ++
            "- parade",
        rendered,
    );
}
