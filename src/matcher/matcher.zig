const std = @import("std");
const expect = std.testing.expect;

const PatternError = error{
    UnclosedGroup,
};

pub fn matches(text: []const u8, pattern: []const u8) PatternError!bool {
    if (pattern[0] == '^')
        return matchesHere(text, pattern[1..]);

    return for (0..text.len) |i| {
        if (try matchesHere(text[i..], pattern)) {
            break true;
        }
    } else false;
}

fn matchesHere(text: []const u8, pattern: []const u8) PatternError!bool {
    std.debug.print("Text: {s}\nPattern: {s}\n", .{ text, pattern });

    if (pattern.len == 0) {
        return true;
    } else if (pattern[0] == '$' and pattern.len == 1) {
        return text.len == 0;
    } else if (pattern.len >= 2 and pattern[1] == '?') {
        if (text.len == 0) {
            return true;
        } else if (text[0] == pattern[0]) {
            return if (text.len == 1 or text[1] != pattern[0]) matchesHere(text[1..], pattern[2..]) else false;
        }

        return matchesHere(text, pattern[2..]);
    } else if (text.len == 0) {
        return false;
    } else if (pattern.len >= 2 and std.mem.eql(u8, pattern[0..2], "\\d") and std.ascii.isDigit(text[0])) {
        return matchesHere(text[1..], pattern[2..]);
    } else if (pattern.len >= 2 and std.mem.eql(u8, pattern[0..2], "\\w") and (std.ascii.isAlphanumeric(text[0]) or text[0] == '_')) {
        return matchesHere(text[1..], pattern[2..]);
    } else if (pattern.len >= 2 and pattern[1] == '+') {
        return matchPlus(text, pattern[0..1], pattern[2..]);
    } else if (pattern[0] == '[') {
        const groupEnd = std.mem.indexOf(u8, pattern, "]") orelse return PatternError.UnclosedGroup;
        const positive, const first_char: usize = if (pattern[1] == '^') .{ false, 2 } else .{ true, 1 };
        const matchesGroup = std.mem.indexOfScalar(u8, pattern[first_char..groupEnd], text[0]) != null;
        return if (matchesGroup == positive) matchesHere(text[1..], if (groupEnd + 1 < pattern.len) pattern[groupEnd + 1 ..] else "") else false;
    } else if (pattern[0] == '.') {
        return matchesHere(text[1..], pattern[1..]);
    }

    return if (text[0] == pattern[0]) matchesHere(text[1..], pattern[1..]) else false;
}

fn matchPlus(text: []const u8, pattern: []const u8, remaining: []const u8) PatternError!bool {
    var i: usize = 1;
    while (i < text.len and matches(text[i..], pattern) catch false) : (i += 1) {}
    i += 1;

    return for (1..i) |j| {
        if (try matchesHere(text[j..], remaining)) {
            break true;
        }
    } else false;
}
