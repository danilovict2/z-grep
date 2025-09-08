const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Node = union(enum) {
    Literal: u8,
};

pub fn parse(allocator: Allocator, pattern: []const u8) ![]Node {
    var nodes = std.ArrayList(Node).init(allocator);
    for (pattern) |c| {
        try nodes.append(.{ .Literal = c });
    }

    return nodes.toOwnedSlice();
}
