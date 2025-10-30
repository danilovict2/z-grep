const std = @import("std");
const parser = @import("parser.zig");
const expect = std.testing.expect;
const Node = parser.Node;
const Quantifier = parser.Quantifier;
const MatchGroups = struct {
    groups: [][]const u8,
};

pub fn matches(text: []const u8, pattern: []const u8) !bool {
    std.debug.print("Text: {s}\nPattern: {s}\n", .{ text, pattern });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const p = try parser.Parser.init(allocator, pattern);
    const nodes = try p.parse();
    var match_groups = MatchGroups{ .groups = try allocator.alloc([]const u8, p.GroupCount) };
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

    var node_index: usize = 0;
    return while (node_index < nodes.len) : (node_index += 1) {
        if (!matchNodes(text, pos, nodes, &node_index, match_groups))
            break false;
    } else true;
}

fn matchNodes(text: []const u8, pos: *usize, nodes: []Node, node_index: *usize, match_groups: *MatchGroups) bool {
    if (nodes.len == 0 or node_index.* >= nodes.len)
        return true;

    const node = nodes[node_index.*];
    const quantifier = node.getQuantifier();
    if (pos.* >= text.len)
        return node == Node.EndOfString or quantifier == Quantifier.ZeroOrOne or quantifier == Quantifier.ZeroOrMore;

    std.debug.print("Current Text: {s}\n", .{text[pos.*..]});
    switch (quantifier) {
        .OneOrMore => {
            std.debug.print("One or More\n", .{});
            return matchRepetition(text, pos, node, nodes, node_index, match_groups, 1, std.math.maxInt(u16));
        },
        .ZeroOrOne => {
            std.debug.print("Zero or One\n", .{});
            _ = matchesNode(text, pos, node, match_groups); // The return value is ignored; only textIndex matters (it increments on match, unchanged otherwise)
        },
        .ZeroOrMore => {
            std.debug.print("Zero or More\n", .{});
            return matchRepetition(text, pos, node, nodes, node_index, match_groups, 0, std.math.maxInt(u16));
        },
        .ExactlyN => |n| {
            std.debug.print("Exactly {} Times\n", .{n});
            var match_count: usize = 0;
            var start_pos = pos.*;
            while (pos.* < text.len and matchesNode(text, pos, node, match_groups)) {
                match_count += if (node == .CharacterGroup) pos.* - start_pos else 1;
                start_pos = pos.*;
            }
            return match_count == n;
        },
        .BetweenNAndM => |between| {
            std.debug.print("At Least {} times and At most {} times\n", .{ between.n, between.m });
            return matchRepetition(text, pos, node, nodes, node_index, match_groups, between.n, between.m);
        },
        .One => {
            if (!matchesNode(text, pos, node, match_groups))
                return false;
        },
    }

    return true;
}

fn matchRepetition(text: []const u8, pos: *usize, node: Node, nodes: []Node, node_index: *usize, match_groups: *MatchGroups, min_match_count: u16, max_match_count: u16) bool {
    const start = pos.*;
    var match_start, var end = .{ start, start };
    var match_count: usize = 0;
    while (end < text.len and matchesNode(text, &end, node, match_groups)) {
        match_count += if (node == .CharacterGroup) end - match_start else 1;
        match_start = end;
    }

    if (match_count < min_match_count or match_count > max_match_count)
        return false;

    node_index.* += 1;
    return while (end > start) : (end -= 1) {
        var cur: usize = end;
        if (matchesPos(text, &cur, nodes[node_index.*..], match_groups)) {
            pos.* = cur;
            node_index.* = nodes.len;
            break true;
        }
    } else false;
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
            const charGroup = group[0][start_index..];
            var matched_any = false;

            while (pos.* < text.len and std.ascii.isAlphanumeric(text[pos.*]) and (std.mem.indexOfScalar(u8, charGroup, text[pos.*]) != null) == is_positive) {
                pos.* += 1;
                matched_any = true;
            }

            return matched_any;
        },
        .Alternation => |alternation| {
            const alternatives = alternation[0];
            return for (alternatives) |alternative| {
                var curr: usize = pos.*;
                if (matchesPos(text, &curr, alternative.Children, match_groups)) {
                    pos.* = curr;
                    break true;
                }
            } else false;
        },
        .Group => |group| {
            if (!matchesPos(text, pos, group.Children, match_groups))
                return false;

            match_groups.*.groups[group.Index] = text[idx..pos.*];
        },
        .Backreference => |n| {
            if (n >= match_groups.*.groups.len)
                return false;

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
