const std = @import("std");
const parser = @import("parser.zig");
const expect = std.testing.expect;
const Node = parser.Node;

const PatternError = error{
    UnclosedGroup,
};

pub fn matches(text: []const u8, pattern: []const u8) !bool {
    std.debug.print("Text: {s}\nPattern: {s}\n", .{ text, pattern });

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const p = try parser.Parser.init(allocator, pattern);
    const nodes = try p.parse();
    return for (0..text.len) |i| {
        if (replacementMatchesHere(text[i..], nodes)) {
            break true;
        }
    } else false;

    //if (pattern[0] == '^')
    //  return matchesHere(text, pattern[1..]);

    // return for (0..text.len) |i| {
    //   if (try matchesHere(text[i..], pattern)) {
    //     break true;
    //}
    //} else false;
    //
}

fn replacementMatchesHere(text: []const u8, nodes: []Node) bool {
    var i: usize = 0;
    for (nodes) |node| {
        if (i == text.len)
            return false;

        switch (node) {
            .Literal => |literal| {
                if (text[i] != literal)
                    return false;
            },
            .CharacterClass => |class| {
                if (std.mem.eql(u8, class, "\\d") and !std.ascii.isDigit(text[i]))
                    return false;

                if (std.mem.eql(u8, class, "\\w") and !(std.ascii.isAlphabetic(text[0]) or text[0] == '_'))
                    return false;
            },
        }

        i += 1;
    }

    return true;
}

fn matchesHere(text: []const u8, pattern: []const u8) PatternError!bool {
    std.debug.print("Text: {s}\nPattern: {s}\n", .{ text, pattern });

    if (pattern.len == 0) {
        return true;
    } else if (pattern[0] == '$' and pattern.len == 1) {
        return text.len == 0;
    } else if (pattern.len >= 2 and pattern[1] == '?') {
        return matchOptional(text, pattern[0..1], pattern[2..]);
    } else if (text.len == 0) {
        return false;
    } else if (pattern.len >= 2 and std.mem.eql(u8, pattern[0..2], "\\d") and std.ascii.isDigit(text[0])) {
        return matchesHere(text[1..], pattern[2..]);
    } else if (pattern.len >= 2 and std.mem.eql(u8, pattern[0..2], "\\w") and (std.ascii.isAlphanumeric(text[0]) or text[0] == '_')) {
        return matchesHere(text[1..], pattern[2..]);
    } else if (pattern.len >= 2 and pattern[1] == '+') {
        return matchPlus(text, pattern[0..1], pattern[2..]);
    } else if (pattern[0] == '[') {
        const groupEnd = try findClosingBracket(pattern, '[', ']');
        const positive, const first_char: usize = if (pattern[1] == '^') .{ false, 2 } else .{ true, 1 };
        const matchesGroup = std.mem.indexOfScalar(u8, pattern[first_char..groupEnd], text[0]) != null;
        return if (matchesGroup == positive) matchesHere(text[1..], if (groupEnd + 1 < pattern.len) pattern[groupEnd + 1 ..] else "") else false;
    } else if (pattern[0] == '(') {
        const closing = try findClosingBracket(pattern, '(', ')');
        const group = pattern[0 .. closing + 1];

        if (pattern.len > (closing + 1)) {
            switch (pattern[closing + 1]) {
                '+' => {
                    return matchPlus(text, group, pattern[closing + 2 ..]);
                },
                '?' => {
                    return matchOptional(text, group, pattern[closing + 2 ..]);
                },
                else => {},
            }
        }

        if (!isAlternationGroup(group))
            return matchesHere(text, group[1 .. group.len - 1]);

        var patterns = std.mem.splitSequence(u8, group[1 .. group.len - 1], "|");
        while (patterns.next()) |p| {
            if (text.len >= p.len and try matches(text, p)) {
                if (pattern.len <= (closing + 1))
                    return true;
                return matchesHere(text[p.len..], pattern[closing + 1 ..]);
            }
        }
    }

    return if (text[0] == pattern[0] or pattern[0] == '.') matchesHere(text[1..], pattern[1..]) else false;
}

fn matchPlus(text: []const u8, pattern: []const u8, remaining: []const u8) PatternError!bool {
    std.debug.print("Plus text, pattern and remaining: {s}, {s}, {s}\n", .{ text, pattern, remaining });
    var i: usize = 0;
    while (i < text.len and matches(text[i..], pattern) catch false) : (i += pattern.len) {}
    i += @min(text.len, i + 1);

    return for (1..i) |j| {
        if (try matchesHere(text[j..], remaining)) {
            break true;
        }
    } else false;
}

fn matchOptional(text: []const u8, pattern: []const u8, remaining: []const u8) PatternError!bool {
    if (text.len == 0) {
        return true;
    } else if (text.len >= pattern.len and matches(text[0..pattern.len], pattern) catch false) {
        if (text[pattern.len..].len < pattern.len) {
            return true;
        } else if (!(matches(text[pattern.len..], pattern) catch false)) {
            return matchesHere(text[pattern.len..], remaining);
        }

        return false;
    }

    return matchesHere(text, remaining);
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
