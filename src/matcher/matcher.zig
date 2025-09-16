const std = @import("std");
const parser = @import("parser.zig");
const expect = std.testing.expect;
const Node = parser.Node;
const Quantifier = parser.Quantifier;

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
        const quantifier = node.getQuantifier();
        if (textIndex == text.len)
            break node == Node.EndOfString or quantifier == Quantifier.ZeroOrOne;

        std.debug.print("Current Text: {s}\n", .{text[textIndex..]});
        switch (quantifier) {
            .OneOrMore => {
                const start = textIndex + 1;
                while (textIndex < text.len and matchesNode(text, &textIndex, nodes[i])) {}
                break for (start..textIndex + 1) |j| {
                    if (try matchesHere(text[j..], nodes[i + 1 ..])) {
                        break true;
                    }
                } else false;
            },
            .ZeroOrOne => {
                _ = matchesNode(text, &textIndex, nodes[i]); // // The return value is ignored; only textIndex matters (it increments on match, unchanged otherwise)
                break matchesHere(text[textIndex..], nodes[i + 1 ..]);
            },
            else => {
                if (!matchesNode(text, &textIndex, node))
                    break false;
            },
        }
    } else true;
}

fn matchesNode(text: []const u8, textIndex: *usize, node: Node) bool {
    node.printSelf();

    const idx = textIndex.*;
    switch (node) {
        .Literal => |literal| {
            if (text[idx] != literal[0])
                return false;
            textIndex.* += 1;
        },
        .CharacterClass => |class| {
            if (std.mem.eql(u8, class[0], "\\d") and !std.ascii.isDigit(text[idx]))
                return false;

            if (std.mem.eql(u8, class[0], "\\w") and !(std.ascii.isAlphanumeric(text[idx]) or text[idx] == '_'))
                return false;

            textIndex.* += 1;
        },
        .Group => |group| {
            const positive, const first_char: usize = if (group[0][0] == '^') .{ false, 1 } else .{ true, 0 };
            const matchesGroup = std.mem.indexOfScalar(u8, group[0][first_char..], text[idx]) != null;
            if (matchesGroup != positive)
                return false;
            textIndex.* += 1;
        },
        .Alternation => |alternation| {
            const alternatives = alternation[0];
            return for (alternatives) |alternative| {
                const match = for (alternative.Children) |child| {
                    if (!matchesNode(text, textIndex, child))
                        break false;
                } else true;

                if (match)
                    break true;
            } else false;
        },
        .EndOfString => {
            return false;
        },
        .Wildcard => {
            textIndex.* += 1;
            return true;
        },
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
