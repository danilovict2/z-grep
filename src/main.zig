const std = @import("std");
const matcher = @import("matcher/matcher.zig");

fn matchPattern(input_line: []const u8, pattern: []const u8) !bool {
    return try matcher.matches(input_line, pattern);
}

fn matchFile(path: []const u8, pattern: []const u8) !bool {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const allocator = std.heap.page_allocator;
    const contents = try file.readToEndAlloc(allocator, 64);
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    var ok: bool = false;
    while (lines.next()) |line| {
        if (try matcher.matches(line, pattern)) {
            try std.io.getStdOut().writeAll(line);
            ok = true;
        }
    }

    return ok;
}

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
    if (args.len == 4) {
        if (try matchFile(args[3], pattern)) {
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
