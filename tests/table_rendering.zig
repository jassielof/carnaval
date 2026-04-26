const std = @import("std");
const carnaval = @import("carnaval");

const allocator = std.testing.allocator;

fn renderTableAlloc(
    headers: []const []const u8,
    rows: []const []const []const u8,
    style: carnaval.TableStyle,
    color_profile: carnaval.ColorProfile,
) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try carnaval.renderTableStyled(allocator, headers, rows, &writer.writer, color_profile, style);
    return writer.toOwnedSlice();
}

test "ascii table renders exact grid output" {
    const rendered = try renderTableAlloc(
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
            &.{ "cli", "warn" },
        },
        .ascii,
        .none,
    );
    defer allocator.free(rendered);

    const expected =
        "+------+--------+\n" ++
        "| Name | Status |\n" ++
        "+------+--------+\n" ++
        "| api  | ok     |\n" ++
        "| cli  | warn   |\n" ++
        "+------+--------+\n";
    try std.testing.expectEqualStrings(expected, rendered);
}

test "markdown table renders exact pipe output" {
    const rendered = try renderTableAlloc(
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
        },
        .markdown,
        .none,
    );
    defer allocator.free(rendered);

    const expected =
        "| Name | Status |\n" ++
        "|------|--------|\n" ++
        "| api  | ok     |\n";
    try std.testing.expectEqualStrings(expected, rendered);
}

test "unicode table renders exact light border output" {
    const rendered = try renderTableAlloc(
        &.{ "名", "Status" },
        &.{
            &.{ "你好", "ok" },
        },
        .unicode,
        .none,
    );
    defer allocator.free(rendered);

    const expected =
        "┌──────┬────────┐\n" ++
        "│ 名   │ Status │\n" ++
        "├──────┼────────┤\n" ++
        "│ 你好 │ ok     │\n" ++
        "└──────┴────────┘\n";
    try std.testing.expectEqualStrings(expected, rendered);
}

test "styled table bolds only header cells" {
    const rendered = try renderTableAlloc(
        &.{ "Name", "Status" },
        &.{
            &.{ "api", "ok" },
        },
        .ascii,
        .ansi16,
    );
    defer allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[1mName\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[1mStatus\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\x1b[1mapi\x1b[0m") == null);
}

test "table rejects rows with wrong column count" {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();

    try std.testing.expectError(
        error.TableColumnCountMismatch,
        carnaval.renderTable(
            allocator,
            &.{ "Name", "Status" },
            &.{
                &.{"api"},
            },
            &writer.writer,
            .ascii,
        ),
    );
}
