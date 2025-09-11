const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Node = union(enum) {
    Literal: u8,
    EndOfString,
    OneOrMore,
    ZeroOrOne,
    CharacterClass: []const u8,
    Group: []const u8,
};

const PatternError = error{
    UnexpectedEOF,
    UnclosedGroup,
    UnexpectedQuantifier,
};

pub const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    raw: []const u8,
    ip: usize = 0,

    pub fn init(a: Allocator, pattern: []const u8) !*Self {
        const self = try a.create(Self);
        self.* = Self{ .allocator = a, .raw = pattern };
        return self;
    }

    pub fn parse(self: *Self) ![]Node {
        var nodes = std.ArrayList(Node).init(self.allocator);
        while (!self.isAtEnd()) {
            const c = self.next();
            switch (c) {
                '\\' => {
                    if (self.isAtEnd())
                        return PatternError.UnexpectedEOF;

                    switch (self.next()) {
                        'd' => try nodes.append(.{ .CharacterClass = "\\d" }),
                        'w' => try nodes.append(.{ .CharacterClass = "\\w" }),
                        else => try nodes.append(.{ .Literal = '\\' }),
                    }
                },
                '[' => {
                    const end = std.mem.indexOfScalar(u8, self.raw[self.ip..], ']') orelse return PatternError.UnclosedGroup;
                    try nodes.append(.{ .Group = self.raw[self.ip .. end + 1] });
                    self.ip = end + 2;
                },
                '$' => try nodes.append(.{ .EndOfString = {} }),
                '+' => {
                    if (nodes.items.len == 0)
                        return PatternError.UnexpectedQuantifier;

                    try nodes.insert(nodes.items.len - 1, .{ .OneOrMore = {} });
                },
                '?' => {
                    if (nodes.items.len == 0)
                        return PatternError.UnexpectedQuantifier;

                    try nodes.insert(nodes.items.len - 1, .{ .ZeroOrOne = {} });
                },
                else => try nodes.append(.{ .Literal = c }),
            }
        }

        return nodes.toOwnedSlice();
    }

    fn peek(self: *Self) ?u8 {
        if (self.isAtEnd())
            return null;

        return self.raw[self.ip];
    }

    fn next(self: *Self) u8 {
        self.advance();
        return self.raw[self.ip - 1];
    }

    fn advance(self: *Self) void {
        self.ip += 1;
    }

    fn isAtEnd(self: *Self) bool {
        return self.ip == self.raw.len;
    }
};
