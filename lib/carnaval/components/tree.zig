//! The tree namespace renders nested terminal trees with configurable branch glyphs.

const std = @import("std");
const Style = @import("../Style.zig");
const ColorProfile = @import("../profile.zig").ColorProfile;

/// The TreeNode structure holds a label, optional children, and visibility state.
pub const TreeNode = struct {
    label: []const u8,
    children: []const TreeNode = &.{},
    hidden: bool = false,
};

/// The TreeOptions structure configures tree glyphs and item styling.
pub const TreeOptions = struct {
    tee: []const u8 = "├── ",
    last: []const u8 = "└── ",
    pipe: []const u8 = "│   ",
    space: []const u8 = "    ",
    style: Style = .{},
    color_profile: ColorProfile = .none,
};

/// The renderAlloc function renders every visible node beneath `root`.
pub fn renderAlloc(allocator: std.mem.Allocator, root: TreeNode, options: TreeOptions) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    try options.style.renderWithProfile(root.label, &writer.writer, options.color_profile);
    try renderChildren(&writer.writer, root.children, "", options);
    return writer.toOwnedSlice();
}

fn renderChildren(writer: *std.Io.Writer, children: []const TreeNode, prefix: []const u8, options: TreeOptions) !void {
    var visible_count: usize = 0;
    for (children) |child| {
        if (!child.hidden) visible_count += 1;
    }
    var visible_index: usize = 0;
    for (children) |child| {
        if (child.hidden) continue;
        const is_last = visible_index + 1 == visible_count;
        try writer.writeByte('\n');
        try writer.writeAll(prefix);
        try writer.writeAll(if (is_last) options.last else options.tee);
        try options.style.renderWithProfile(child.label, writer, options.color_profile);
        var next_prefix = std.Io.Writer.Allocating.init(std.heap.page_allocator);
        defer next_prefix.deinit();
        try next_prefix.writer.writeAll(prefix);
        try next_prefix.writer.writeAll(if (is_last) options.space else options.pipe);
        const owned = try next_prefix.toOwnedSlice();
        defer std.heap.page_allocator.free(owned);
        try renderChildren(writer, child.children, owned, options);
        visible_index += 1;
    }
}

test "renderAlloc renders nested and hidden nodes" {
    const output = try renderAlloc(std.testing.allocator, .{ .label = "root", .children = &.{ .{ .label = "one" }, .{ .label = "two", .children = &.{.{ .label = "leaf" }} }, .{ .label = "hidden", .hidden = true } } }, .{});
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("root\n├── one\n└── two\n    └── leaf", output);
}
