const std = @import("std");
const parser = @import("parser.zig");
const expect = std.testing.expect;
const Node = parser.Node;
const Quantifier = parser.Quantifier;
const MatchGroups = struct {
    groups: [][]const u8,
    current: u8 = 0,
};

pub fn matches(text: []const u8, pattern: []const u8) !bool {
    std.debug.print("Text: {s}\nPattern: {s}\n", .{ text, pattern });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const p = try parser.Parser.init(allocator, pattern);
    const nodes = try p.parse();
    var groups: usize = 0;
    for (nodes) |node| {
        switch (node) {
            .Group => groups += 1,
            else => {},
        }
    }

    var match_groups = MatchGroups{ .groups = try allocator.alloc([]const u8, groups) };
    var pos: usize = 0;
    if (pattern[0] == '^')
        return matchesPos(text, &pos, nodes[1..], &match_groups);

    return for (0..text.len) |i| {
        pos = i;
        if (matchesPos(text, &pos, nodes, &match_groups)) {
            break true;
        }
    } else false;
}

fn matchesPos(text: []const u8, pos: *usize, nodes: []Node, match_groups: *MatchGroups) bool {
    std.debug.print("Starting Text: {s}\n", .{text});

    var nodeIndex: usize = 0;
    return while (nodeIndex < nodes.len) : (nodeIndex += 1) {
        if (!matchNodes(text, pos, nodes, &nodeIndex, match_groups))
            break false;
    } else true;
}

fn matchNodes(text: []const u8, pos: *usize, nodes: []Node, nodeIndex: *usize, match_groups: *MatchGroups) bool {
    if (nodes.len == 0 or nodeIndex.* >= nodes.len)
        return true;

    const node = nodes[nodeIndex.*];
    const quantifier = node.getQuantifier();
    if (pos.* >= text.len)
        return node == Node.EndOfString or quantifier == Quantifier.ZeroOrOne;

    std.debug.print("Current Text: {s}\n", .{text[pos.*..]});
    switch (quantifier) {
        .OneOrMore => {
            std.debug.print("One or More\n", .{});

            const start = pos.*;
            var end: usize = start;
            while (end < text.len and matchesNode(text, &end, node, match_groups)) {}
            if (end == start)
                return false;

            nodeIndex.* += 1;
            return while (end > start) : (end -= 1) {
                if (matchNodes(text, &end, nodes, nodeIndex, match_groups)) {
                    pos.* = end;
                    return true;
                }
            } else false;
        },
        .ZeroOrOne => {
            std.debug.print("Zero or One\n", .{});
            _ = matchesNode(text, pos, node, match_groups); // // The return value is ignored; only textIndex matters (it increments on match, unchanged otherwise)
        },
        else => {
            if (!matchesNode(text, pos, node, match_groups))
                return false;
        },
    }

    return true;
}

fn matchesNode(text: []const u8, pos: *usize, node: Node, match_groups: *MatchGroups) bool {
    node.printSelf();

    const idx = pos.*;
    switch (node) {
        .Literal => |literal| {
            if (text[idx] != literal[0])
                return false;
            pos.* += 1;
        },
        .CharacterClass => |class| {
            if (std.mem.eql(u8, class[0], "\\d") and !std.ascii.isDigit(text[idx]))
                return false;

            if (std.mem.eql(u8, class[0], "\\w") and !(std.ascii.isAlphanumeric(text[idx]) or text[idx] == '_'))
                return false;

            pos.* += 1;
        },
        .CharacterGroup => |group| {
            const is_positive, const start_index: usize = if (group[0][0] == '^') .{ false, 1 } else .{ true, 0 };
            var matches_group = std.mem.indexOfScalar(u8, group[0][start_index..], text[idx]) != null;
            const match = matches_group == is_positive;

            while (pos.* < (text.len - 1) and matches_group == is_positive) {
                pos.* += 1;
                matches_group = std.mem.indexOfScalar(u8, group[0][start_index..], text[pos.*]) != null;
            }

            return match;
        },
        .Alternation => |alternation| {
            const alternatives = alternation[0];
            return for (alternatives) |alternative| {
                if (matchesPos(text, pos, alternative.Children, match_groups))
                    break true;
            } else false;
        },
        .Group => |group| {
            if (!matchesPos(text, pos, group.Children, match_groups))
                return false;

            if (match_groups.*.current >= match_groups.*.groups.len)
                return false;
            match_groups.*.groups[match_groups.*.current] = text[idx..pos.*];
            match_groups.*.current += 1;
        },
        .Backreference => |n| {
            std.debug.print("N: {}; Groups Len: {}\n", .{ n, match_groups.*.groups.len });
            if (n >= match_groups.*.current)
                return false;

            std.debug.print("Group: {s}; Text: {s}\n", .{ match_groups.*.groups[n], text[idx..] });

            if (std.mem.startsWith(u8, text[idx..], match_groups.*.groups[n])) {
                pos.* += match_groups.*.groups[n].len;
                return true;
            }

            return false;
        },
        .EndOfString => {
            return false;
        },
        .Wildcard => {
            pos.* += 1;
            return true;
        },
    }

    return true;
}
