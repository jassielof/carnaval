//! The canvas namespace provides a cell-addressed terminal drawing surface.

const std = @import("std");

/// The Canvas structure stores a rectangular grid of UTF-8 cell strings.
pub const Canvas = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    cells: []?[]u8,

    /// The init function creates a blank canvas with the requested dimensions.
    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        const cells = try allocator.alloc(?[]u8, width * height);
        @memset(cells, null);
        return .{ .allocator = allocator, .width = width, .height = height, .cells = cells };
    }

    /// The deinit function frees every cell owned by the canvas.
    pub fn deinit(self: *Canvas) void {
        for (self.cells) |cell| if (cell) |value| self.allocator.free(value);
        self.allocator.free(self.cells);
    }

    /// The set function copies a cell value when it lies inside the canvas.
    pub fn set(self: *Canvas, x: usize, y: usize, value: []const u8) !void {
        if (x >= self.width or y >= self.height) return error.OutOfBounds;
        const index = y * self.width + x;
        if (self.cells[index]) |old| self.allocator.free(old);
        self.cells[index] = try self.allocator.dupe(u8, value);
    }

    /// The clear function removes all drawn cells.
    pub fn clear(self: *Canvas) void {
        for (self.cells) |*cell| {
            if (cell.*) |value| self.allocator.free(value);
            cell.* = null;
        }
    }

    /// The renderAlloc function returns the canvas as newline-delimited terminal text.
    pub fn renderAlloc(self: *const Canvas, allocator: std.mem.Allocator) ![]u8 {
        var writer = std.Io.Writer.Allocating.init(allocator);
        defer writer.deinit();
        for (0..self.height) |y| {
            for (0..self.width) |x| try writer.writer.writeAll(self.cells[y * self.width + x] orelse " ");
            if (y + 1 < self.height) try writer.writer.writeByte('\n');
        }
        return writer.toOwnedSlice();
    }
};

test "Canvas renders a cell grid" {
    var canvas = try Canvas.init(std.testing.allocator, 3, 2);
    defer canvas.deinit();
    try canvas.set(1, 0, "X");
    const result = try canvas.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(" X \n   ", result);
}
