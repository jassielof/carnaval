const std = @import("std");
const carnaval = @import("carnaval");

const allocator = std.testing.allocator;

test "style render exact ansi16 escape sequence order" {
    const style = carnaval.Style.init()
        .bolded()
        .dimmed()
        .italicized()
        .underlined()
        .striked()
        .fg(.{ .ansi16 = .red })
        .bg(.{ .ansi16 = .blue });

    const rendered = try style.renderAllocWithProfile("go", allocator, .ansi16);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[1m\x1b[2m\x1b[3m\x1b[4m\x1b[9m\x1b[31m\x1b[44mgo\x1b[0m",
        rendered,
    );
}

test "style render exact true color foreground and background" {
    const style = carnaval.Style.init()
        .fg(carnaval.Color.rgb(12, 34, 56))
        .bg(carnaval.Color.rgb(200, 201, 202));

    const rendered = try style.renderAllocWithProfile("rgb", allocator, .true_color);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[38;2;12;34;56m\x1b[48;2;200;201;202mrgb\x1b[0m",
        rendered,
    );
}

test "style render downsampled ansi256 profile" {
    const style = carnaval.Style.init()
        .fg(carnaval.Color.rgb(255, 0, 0))
        .bg(.{ .ansi16 = .bright_blue });

    const rendered = try style.renderAllocWithProfile("color", allocator, .ansi256);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "\x1b[38;5;196m\x1b[48;5;12mcolor\x1b[0m",
        rendered,
    );
}

test "style render writes plain text when profile disables color" {
    const style = carnaval.Style.init()
        .bolded()
        .fg(.{ .ansi16 = .green });

    const rendered = try style.renderAllocWithProfile("plain", allocator, .none);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings("plain", rendered);
}

test "style writer output matches allocating render" {
    const style = carnaval.Style.init()
        .underlined()
        .fg(.{ .ansi256 = 42 });
    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try style.renderWithProfile("writer", &writer, .ansi256);

    const allocated = try style.renderAllocWithProfile("writer", allocator, .ansi256);
    defer allocator.free(allocated);

    try std.testing.expectEqualStrings(allocated, writer.buffered());
}
