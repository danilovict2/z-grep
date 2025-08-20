const std = @import("std");
const expect = std.testing.expect;
const matcher = @import("matcher.zig");

test "Match Literal Character" {
    try expect(try matcher.matches("apple", "a"));
    try expect(!try matcher.matches("dog", "a"));
}

test "Match digits" {
    try expect(try matcher.matches("1 apple", "\\d apple"));
    try expect(!try matcher.matches("1 orange", "\\d apple"));
    try expect(try matcher.matches("100 apples", "\\d\\d\\d apple"));
    try expect(!try matcher.matches("100 oranges", "\\d\\d\\d apple"));
}

test "Match word characters" {
    try expect(try matcher.matches("alpha_num3ric", "\\w"));
}

test "Match positive character groups" {
    try expect(try matcher.matches("apple", "[abc]"));
    try expect(try matcher.matches("nbc", "[mango]"));
    try expect(!try matcher.matches("dog", "[abc]"));
    try expect(!try matcher.matches("orange", "[bcdfhi]"));
}

test "Match negative character groups" {
    try expect(try matcher.matches("apple", "[^xyz]"));
    try expect(try matcher.matches("apple", "[^abc]"));
    try expect(!try matcher.matches("banana", "[^anb]"));
}

test "Combining character classes" {
    try expect(try matcher.matches("sally has 3 apples", "\\d apple"));
    try expect(try matcher.matches("4 dogs", "\\d \\w\\w\\ws"));
    try expect(try matcher.matches("4 cats", "\\d \\w\\w\\ws"));
    try expect(!try matcher.matches("1 dog", "\\d \\w\\w\\ws"));
}

test "Start of string anchor" {
    try expect(try matcher.matches("log", "^log"));
    try expect(!try matcher.matches("slog", "^log"));
}

test "End of string anchor" {
    try expect(try matcher.matches("dog", "dog$"));
    try expect(!try matcher.matches("dogs", "dog$"));
}

test "Match one or more times" {
    try expect(try matcher.matches("caats", "ca+ts"));
    try expect(!try matcher.matches("act", "ca+t"));
}

test "Match zero or one times" {
    try expect(try matcher.matches("dogs", "dogs?"));
    try expect(try matcher.matches("dog", "dogs?"));
    try expect(!try matcher.matches("cat", "dogs?"));
}

test "Wildcard" {
    try expect(try matcher.matches("dog", "d.g"));
    try expect(!try matcher.matches("cog", "d.g"));
    try expect(try matcher.matches("goøö0Ogol", "g.+gol"));
}
