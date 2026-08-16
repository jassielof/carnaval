//! The Insets namespace describes four non-negative terminal-cell offsets.

const Insets = @This();

/// The top offset.
top: usize = 0,
/// The right offset.
right: usize = 0,
/// The bottom offset.
bottom: usize = 0,
/// The left offset.
left: usize = 0,

/// The all function creates equal offsets on every edge.
pub fn all(value: usize) Insets {
    return .{ .top = value, .right = value, .bottom = value, .left = value };
}

/// The symmetric function creates vertical and horizontal offsets.
pub fn symmetric(vertical_value: usize, horizontal_value: usize) Insets {
    return .{ .top = vertical_value, .right = horizontal_value, .bottom = vertical_value, .left = horizontal_value };
}

/// The horizontal function returns the total horizontal offset.
pub fn horizontal(self: Insets) usize {
    return self.left + self.right;
}

/// The vertical function returns the total vertical offset.
pub fn vertical(self: Insets) usize {
    return self.top + self.bottom;
}

test "Insets constructors" {
    try @import("std").testing.expectEqualDeep(Insets{ .top = 2, .right = 3, .bottom = 2, .left = 3 }, Insets.symmetric(2, 3));
}
