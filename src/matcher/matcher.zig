const std = @import("std");
const parser = @import("parser.zig");
const expect = std.testing.expect;
const Node = parser.Node;

const PatternError = error{
    InvalidPattern,
};

pub fn matches(text: []const u8, pattern: []const u8) !bool {
    std.debug.print("Text: {s}\nPattern: {s}\n", .{ text, pattern });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const p = try parser.Parser.init(allocator, pattern);
    const nodes = try p.parse();

    if (pattern[0] == '^')
        return matchesHere(text, nodes[1..]);

    return for (0..text.len) |i| {
        if (try matchesHere(text[i..], nodes)) {
            break true;
        }
    } else false;
}

fn matchesHere(text: []const u8, nodes: []Node) PatternError!bool {
    std.debug.print("Starting Text: {s}\n", .{text});
    var textIndex: usize = 0;
    return for (nodes, 0..) |node, i| {
        if (textIndex == text.len)
            break node == Node.EndOfString or node == Node.ZeroOrOne;

        std.debug.print("Current Text: {s}\n", .{text[textIndex..]});
        switch (node) {
            .OneOrMore => {
                std.debug.print("One Or More\n", .{});
                if ((i + 1) == nodes.len)
                    return PatternError.InvalidPattern;

                const start = textIndex;
                while (textIndex < text.len and matchesNode(text, textIndex, nodes[i + 1])) : (textIndex += 1) {}
                break for (start..textIndex + 1) |j| {
                    if (try matchesHere(text[j..], nodes[i + 1 ..])) {
                        break true;
                    }
                } else false;
            },
            .ZeroOrOne => {
                std.debug.print("Zero Or One\n", .{});
                if ((i + 1) == nodes.len)
                    return PatternError.InvalidPattern;

                if (matchesNode(text, textIndex, nodes[i + 1])) // Matches
                    break matchesHere(text[textIndex + 1 ..], nodes[i + 2 ..]);

                break matchesHere(text[textIndex..], nodes[i + 2 ..]);
            },
            else => {
                if (!matchesNode(text, textIndex, node))
                    break false;
            },
        }

        textIndex += 1;
    } else true;
}

fn matchesNode(text: []const u8, textIndex: usize, node: Node) bool {
    switch (node) {
        .Literal => |literal| {
            std.debug.print("Literal: {c}\n", .{literal});
            if (text[textIndex] != literal)
                return false;
        },
        .CharacterClass => |class| {
            std.debug.print("Class: {s}\n", .{class});
            if (std.mem.eql(u8, class, "\\d") and !std.ascii.isDigit(text[textIndex]))
                return false;

            if (std.mem.eql(u8, class, "\\w") and !(std.ascii.isAlphanumeric(text[textIndex]) or text[textIndex] == '_'))
                return false;
        },
        .Group => |group| {
            std.debug.print("Group: {s}\n", .{group});
            const positive, const first_char: usize = if (group[0] == '^') .{ false, 1 } else .{ true, 0 };
            const matchesGroup = std.mem.indexOfScalar(u8, group[first_char..], text[textIndex]) != null;
            if (matchesGroup != positive)
                return false;
        },
        .EndOfString => {
            return false;
        },
        .Wildcard => {
            std.debug.print("Wildcard\n", .{});
            return true;
        },
        else => unreachable,
    }

    return true;
}

fn findClosingBracket(str: []const u8, open: u8, closed: u8) PatternError!usize {
    var counter: usize = 0;

    return for (str, 0..) |c, i| {
        if (c == open)
            counter += 1;
        if (c == closed)
            counter -= 1;
        if (counter == 0)
            break i;
    } else PatternError.UnclosedGroup;
}

fn isAlternationGroup(pattern: []const u8) bool {
    if (pattern.len < 2 or pattern[0] != '(' or pattern[pattern.len - 1] != ')')
        return false;

    var depth: usize = 0;
    var hasTopLevelPipe = false;

    for (pattern[1 .. pattern.len - 1]) |c| {
        switch (c) {
            '(' => depth += 1,
            ')' => {
                if (depth > 0) depth -= 1;
            },
            '|' => {
                if (depth == 0) hasTopLevelPipe = true;
            },
            else => {},
        }
    }

    return hasTopLevelPipe;
}
