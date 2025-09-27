const std = @import("std");
const matcher = @import("matcher/matcher.zig");
const FILE_MAX_LEN: usize = 1024;
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or !(std.mem.eql(u8, args[1], "-E") or std.mem.eql(u8, args[2], "-E"))) {
        std.debug.print("Expected first or second argument to be '-E'\n", .{});
        std.process.exit(1);
    }

    const recurse = std.mem.eql(u8, args[1], "-r");
    const pattern = if (recurse) args[3] else args[2];

    var matched = false;

    if (args.len > 3) {
        if (recurse) {
            matched = try recursiveSearch(args[4], pattern, allocator);
        } else {
            matched = try matchFiles(args[3..], pattern, allocator);
        }
    } else {
        var input_line: [1024]u8 = undefined;
        const input_len = try std.io.getStdIn().reader().read(&input_line);
        const input_slice = input_line[0..input_len];
        matched = try matchPattern(input_slice, pattern);
    }

    exitWithResult(matched);
}

fn recursiveSearch(dir_path: []const u8, pattern: []const u8, allocator: std.mem.Allocator) !bool {
    const clean = std.mem.trimRight(u8, dir_path, "/");
    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var ok: bool = false;
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ clean, entry.path });
                if (matchFile(path, pattern, allocator)) |matchingLines| {
                    if (matchingLines.len > 0) {
                        ok = true;
                        try stdout.print("{s}:", .{path});
                        for (matchingLines) |line|
                            try stdout.print("{s}\n", .{line});
                    }
                } else |err| {
                    return err;
                }
            },
            else => {},
        }
    }

    return ok;
}

fn matchFiles(paths: [][:0]u8, pattern: []const u8, allocator: std.mem.Allocator) !bool {
    var ok: bool = false;
    for (paths) |path| {
        if (matchFile(path, pattern, allocator)) |matchingLines| {
            for (matchingLines) |line| {
                if (paths.len > 1)
                    try stdout.print("{s}:", .{path});

                try stdout.print("{s}\n", .{line});
            }
            ok = ok or matchingLines.len > 0;
        } else |err| {
            return err;
        }
    }

    return ok;
}

fn matchFile(path: []const u8, pattern: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, FILE_MAX_LEN);
    defer allocator.free(contents);

    var matchingLines = std.ArrayList([]const u8).init(allocator);
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (try matcher.matches(line, pattern)) {
            const dup_line = try allocator.dupe(u8, line);
            try matchingLines.append(dup_line);
        }
    }

    return matchingLines.toOwnedSlice();
}

fn matchPattern(input_line: []const u8, pattern: []const u8) !bool {
    return matcher.matches(input_line, pattern);
}

fn exitWithResult(matched: bool) noreturn {
    if (matched) {
        std.debug.print("Match\n", .{});
        std.process.exit(0);
    }

    std.debug.print("Not a match\n", .{});
    std.process.exit(1);
}
