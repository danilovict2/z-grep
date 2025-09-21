const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Quantifier = enum { One, OneOrMore, ZeroOrOne };

const Group = struct { Children: []Node, Quantifier: Quantifier };

pub const Node = union(enum) {
    Literal: struct { u8, Quantifier },
    EndOfString,
    Wildcard: struct { Quantifier },
    CharacterClass: struct { []const u8, Quantifier },
    CharacterGroup: struct { []const u8, Quantifier },
    Group: Group,
    Alternation: struct { []Group, Quantifier },

    pub fn printSelf(self: @This()) void {
        switch (self) {
            .Literal => |literal| {
                std.debug.print("Literal: {c}\n", .{ literal[0]  });
            },
            .EndOfString => {
                std.debug.print("End Of String\n", .{});
            },
            .Wildcard => {
                std.debug.print("Wildcard\n", .{});
            },
            .CharacterClass => |class| {
                std.debug.print("Class: {s}\n", .{class[0]});
            },
            .CharacterGroup => |group| {
                std.debug.print("Character Group: {s}\n", .{group[0]});
            },
            .Alternation => |alternation| {
                const alternatives = alternation[0];
                for (alternatives, 0..) |alternative, i| {
                    std.debug.print("Alternative {}\n", .{i});
                    for (alternative.Children) |child|
                        child.printSelf();
                }
            },
            .Group => |group| {
                std.debug.print("Group:\n", .{});
                for (group.Children) |child|
                    child.printSelf();
            },
        }
    }

    pub fn getQuantifier(self: @This()) Quantifier {
        return switch (self) {
            .Literal => |literal| literal[1],
            .Wildcard => |wildcard| wildcard[0],
            .CharacterClass => |class| class[1],
            .Group => |group| group.Quantifier,
            .CharacterGroup => |group| group[1],
            .Alternation => |alternation| alternation[1],
            .EndOfString => Quantifier.One,
        };
    }
};

const PatternError = error{
    UnexpectedEOF,
    UnclosedGroup,
    UnexpectedQuantifier,
    InvalidBackreference,
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
                        'd' => try nodes.append(.{ .CharacterClass = .{ "\\d", Quantifier.One } }),
                        'w' => try nodes.append(.{ .CharacterClass = .{ "\\w", Quantifier.One } }),
                        '1' => try nodes.append(try parseBackreference(nodes)),
                        else => try nodes.append(.{ .Literal = .{ '\\', Quantifier.One } }),
                    }
                },
                '[' => {
                    const end = std.mem.indexOfScalarPos(u8, self.raw, self.ip, ']') orelse return PatternError.UnclosedGroup;
                    try nodes.append(.{ .CharacterGroup = .{ self.raw[self.ip..end], Quantifier.One } });
                    self.ip = end + 2;
                },
                '$' => try nodes.append(.{ .EndOfString = {} }),
                '+' => {
                    try setLastQuantifier(&nodes, Quantifier.OneOrMore);
                },
                '?' => {
                    try setLastQuantifier(&nodes, Quantifier.ZeroOrOne);
                },
                '.' => try nodes.append(.{ .Wildcard = .{Quantifier.One} }),
                '(' => {
                    const group = try self.parseGroup();
                    try nodes.append(.{ .Group = group });
                },
                '|', ')' => {
                    self.ip -= 1;
                    break;
                },
                else => try nodes.append(.{ .Literal = .{ c, Quantifier.One } }),
            }
        }

        return nodes.toOwnedSlice();
    }

    fn parseBackreference(nodes: std.ArrayList(Node)) PatternError!Node {
        var i: usize = nodes.items.len;
        while (i > 0) {
            i -= 1;
            switch (nodes.items[i]) {
                .Group => {
                    return nodes.items[i];
                },
                else => {},
            }
        }

        return PatternError.InvalidBackreference;
    }

    fn setLastQuantifier(nodes: *std.ArrayList(Node), q: Quantifier) PatternError!void {
        if (nodes.items.len == 0)
            return PatternError.UnexpectedQuantifier;

        const last = &nodes.items[nodes.items.len - 1];
        switch (last.*) {
            .Literal => |*lit| lit.*[1] = q,
            .Wildcard => |*wc| wc.*[0] = q,
            .CharacterClass => |*cc| cc.*[1] = q,
            .Group => |*grp| grp.*.Quantifier = q,
            .CharacterGroup => |*grp| grp.*[1] = q,
            .Alternation => |*alt| alt.*[1] = q,
            .EndOfString => return PatternError.UnexpectedQuantifier,
        }
    }

    fn parseGroup(self: *Self) (PatternError || std.mem.Allocator.Error)!Group {
        var children = std.ArrayList(Node).init(self.allocator);
        var partedParts = std.ArrayList(Group).init(self.allocator);

        while (true) {
            if (self.peek()) |nxt| {
                switch (nxt) {
                    ')' => {
                        self.advance();
                        break;
                    },
                    '|' => {
                        try partedParts.append(.{ .Children = try children.toOwnedSlice(), .Quantifier = Quantifier.One });
                        self.advance();
                    },
                    else => {},
                }
            }

            const nodes = try self.parse();
            try children.appendSlice(nodes);
        }

        if (partedParts.items.len > 0) {
            try partedParts.append(.{ .Children = try children.toOwnedSlice(), .Quantifier = Quantifier.One });
            try children.append(.{ .Alternation = .{ try partedParts.toOwnedSlice(), Quantifier.One } });
        }

        const ownedChildren = try children.toOwnedSlice();
        return .{ .Children = ownedChildren, .Quantifier = Quantifier.One };
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
        return self.ip >= self.raw.len;
    }
};
