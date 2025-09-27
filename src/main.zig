const std = @import("std");
const matcher = @import("matcher/matcher.zig");
const FILE_MAX_LEN: usize = 512;

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or !std.mem.eql(u8, args[1], "-E")) {
        std.debug.print("Expected first argument to be '-E'\n", .{});
        std.process.exit(1);
    }

    const pattern = args[2];
    if (args.len > 3) {
        if (try matchFiles(args[3..], pattern, allocator)) {
            std.debug.print("Match\n", .{});
            std.process.exit(0);
        }

        std.debug.print("Not a match\n", .{});
        std.process.exit(1);
    }

    var input_line: [1024]u8 = undefined;
    const input_len = try std.io.getStdIn().reader().read(&input_line);
    const input_slice = input_line[0..input_len];

    if (try matchPattern(input_slice, pattern)) {
        std.debug.print("Match\n", .{});
        std.process.exit(0);
    }

    std.debug.print("Not a match\n", .{});
    std.process.exit(1);
}

fn matchFiles(paths: [][:0]u8, pattern: []const u8, allocator: std.mem.Allocator) !bool {
    var ok: bool = false;
    for (paths) |path| {
        if (matchFile(path, pattern, allocator)) |matchingLines| {
            for (matchingLines) |line| {
                if (paths.len > 1) {
                    try std.io.getStdOut().writeAll(path);
                    try std.io.getStdOut().writeAll(":");
                }

                try std.io.getStdOut().writeAll(line);
                try std.io.getStdOut().writeAll("\n");
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
