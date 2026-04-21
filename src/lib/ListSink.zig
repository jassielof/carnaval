//! 
const std = @import("std");

const ListSink = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: *ListSink, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }
};
