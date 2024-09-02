const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});

pub fn main() anyerror!void {
    // TODO: use something other than arena here.
    // want to free up allocations after each test (probably?).
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var exit_code: u8 = 0;
    run(arena.allocator()) catch |err| {
        exit_code = 1;
        if (err != error.Explained) {
            return err;
        }
    };

    std.process.exit(exit_code);
}

pub fn run(alloc: std.mem.Allocator) !void {
    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();

    _ = args_iter.next(); // program name

    const cwd = std.fs.cwd();

    const params = try Params.parse(&args_iter);
    if (params.tig) |tig| {
        // TODO: handle the case when the binary isn't named 'tig'.
        const tig_abs = try cwd.realpathAlloc(alloc, tig);
        defer alloc.free(tig_abs);

        const tig_dir = std.fs.path.dirname(tig_abs) orelse unreachable;
        try prependPathDir(alloc, tig_dir);
    }

    if (params.test_graph) |test_graph| {
        const test_graph_abs = try cwd.realpathAlloc(alloc, test_graph);
        defer alloc.free(test_graph_abs);

        const test_graph_dir = std.fs.path.dirname(test_graph_abs) orelse unreachable;
        try prependPathDir(alloc, test_graph_dir);
    }

    var test_dir = try cwd.openDir(params.dir, .{ .iterate = true });
    defer test_dir.close();

    try test_dir.setAsCwd();

    var test_walk = try test_dir.walk(alloc);
    defer test_walk.deinit();

    var stdout_buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer stdout_buffer.flush() catch unreachable;
    var stdout = stdout_buffer.writer();

    while (try test_walk.next()) |ent| {
        if (ent.kind != .file) continue;
        if (!std.mem.endsWith(u8, ent.path, "-test")) continue;

        if (params.list) {
            try stdout.print("{s}\n", .{ent.path});
            continue;
        }

        std.log.debug("{s}", .{ent.path});
        var child = std.process.Child.init(&.{ent.path}, alloc);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = try child.spawnAndWait();
        exitOk(term) catch |err| {
            if (err == error.NonZeroStatus) {
                std.log.err("FAIL: {s}", .{ent.path});
            }
            return err;
        };
        // TODO: flag to fail fast
    }

    // TODO: port show-results into this program
    if (!params.list) {
        const show_results = try test_dir.realpathAlloc(alloc, "tools/show-results.sh");
        defer alloc.free(show_results);

        // foo/test/tools/show-results.sh => foo
        const tools_dir = std.fs.path.dirname(show_results) orelse unreachable;
        const test_dir_path = std.fs.path.dirname(tools_dir) orelse unreachable;
        const root_dir = std.fs.path.dirname(test_dir_path) orelse unreachable;

        var child = std.process.Child.init(&.{show_results}, alloc);
        child.cwd = root_dir;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        const term = try child.spawnAndWait();
        try exitOk(term);
    }
}

/// Params defines the command line arguments.
const Params = struct {
    pub const Error = error{Explained};

    dir: []const u8, // directory containing the tests
    list: bool, // list the tests and exit

    tig: ?[]const u8, // path to the tig executable
    test_graph: ?[]const u8, // path to the test-graph binary

    pub fn parse(args: anytype) Error!Params {
        // TODO: flag to filter tests
        var dir: ?[]const u8 = null;
        var tig: ?[]const u8 = null;
        var test_graph: ?[]const u8 = null;
        var list = false;

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "-d")) {
                dir = args.next() orelse {
                    std.log.err("expected an argument after -d", .{});
                    return error.Explained;
                };
            } else if (std.mem.eql(u8, arg, "--list")) {
                list = true;
            } else if (std.mem.eql(u8, arg, "--tig")) {
                tig = args.next() orelse {
                    std.log.err("expected an argument after --tig", .{});
                    return error.Explained;
                };
            } else if (std.mem.eql(u8, arg, "--test-graph")) {
                test_graph = args.next() orelse {
                    std.log.err("expected an argument after --test-graph", .{});
                    return error.Explained;
                };
            } else {
                std.log.err("unexpected argument: {s}", .{arg});
                return error.Explained;
            }
        }

        return Params{
            .dir = dir orelse "test",
            .list = list,
            .tig = tig,
            .test_graph = test_graph,
        };
    }
};

fn exitOk(term: std.process.Child.Term) !void {
    switch (term) {
        .Exited => |code| if (code != 0) {
            return error.NonZeroStatus;
        },
        else => {
            return error.UnexpectedTermination;
        },
    }
}

fn prependPathDir(alloc: std.mem.Allocator, dir: []const u8) !void {
    const prev_path = try std.process.getEnvVarOwned(alloc, "PATH");
    defer alloc.free(prev_path);

    var new_path: [:0]u8 = undefined;
    if (prev_path.len > 0) {
        new_path = try std.fmt.allocPrintZ(
            alloc,
            "{s}" ++ [1]u8{std.fs.path.delimiter} ++ "{s}",
            .{ dir, prev_path },
        );
    } else {
        new_path = try alloc.dupeZ(u8, dir);
    }
    defer alloc.free(new_path);

    if (c.setenv("PATH", new_path.ptr, 1) != 0) {
        return error.PosixError;
    }
}
