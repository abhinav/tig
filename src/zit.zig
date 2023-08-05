const std = @import("std");
const c = @import("./c.zig");

pub usingnamespace @import("string.zig");

pub fn main() !void {
    const code = c.tig_main(@intCast(std.os.argv.len), @ptrCast(std.os.argv.ptr));
    std.process.exit(@intCast(code));
}
