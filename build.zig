const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compat = b.addObject(.{
        .name = "compat",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    compat.addIncludePath(.{ .path = "compat" });
    compat.addCSourceFiles(&.{
        "compat/hashtab.c",
        "compat/mkstemps.c",
        "compat/setenv.c",
        "compat/strndup.c",
        "compat/utf8proc.c",
        "compat/wordexp.c",
    }, &.{});

    const graph = b.addObject(.{
        .name = "graph",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    graph.addIncludePath(.{ .path = "." });
    graph.addIncludePath(.{ .path = "include" });
    graph.addCSourceFiles(&.{
        "src/graph-v1.c",
        "src/graph-v2.c",
        "src/graph.c",
    }, &.{});

    const zit = b.addObject(.{
        .name = "zit",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/zit.zig" },
        .link_libc = true,
    });
    zit.addIncludePath(.{ .path = "." });
    zit.addIncludePath(.{ .path = "include" });

    const make_builtin_config = b.addSystemCommand(&.{"./tools/make-builtin-config.sh"});
    make_builtin_config.addFileSourceArg(std.Build.FileSource.relative("tigrc"));
    // Hack: captureStdOut does not allow specifying the name of the file.
    // As a workaround, change the configuration of the Output object
    // after having captureStdOut wire it up.
    const builtin_config = make_builtin_config.captureStdOut();
    make_builtin_config.captured_stdout.?.basename = "builtin-config.c";

    const tig = b.addObject(.{
        .name = "tig",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tig.step.dependOn(&make_builtin_config.step);
    tig.defineCMacro("SYSCONFDIR", "\"/etc\"");
    tig.defineCMacro("TIG_VERSION", "\"1.2.3-dev\"");
    tig.defineCMacro("UINT16_MAX", "65535");
    tig.defineCMacro("false", "0");
    tig.defineCMacro("true", "1");
    tig.addIncludePath(.{ .path = "." });
    tig.addIncludePath(.{ .path = "include" });
    tig.addCSourceFiles(&tig_c_files, &.{});
    tig.addCSourceFile(.{ .file = builtin_config, .flags = &.{} });

    const exe = b.addExecutable(.{
        .name = "tig",
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    exe.strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;
    exe.addObject(zit);
    exe.addObject(tig);
    exe.addObject(compat);
    exe.addObject(graph);
    exe.linkSystemLibrary("ncursesw");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zit.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Needed for integration tests.
    const test_graph = b.addExecutable(.{
        .name = "test-graph",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_graph.addIncludePath(.{ .path = "." });
    test_graph.addIncludePath(.{ .path = "include" });
    test_graph.addCSourceFiles(&.{
        "test/tools/test-graph.c",
        "src/string.c",
        "src/util.c",
        "src/io.c",
    }, &.{});
    test_graph.addObject(compat);
    test_graph.addObject(graph);
    test_graph.linkSystemLibrary("ncursesw");

    const integration_tests = b.addExecutable(.{
        .name = "integration-test-runner",
        .root_source_file = .{ .path = "test/integration.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.step.dependOn(&exe.step);
    run_integration_tests.step.dependOn(&test_graph.step);
    {
        const test_tools = b.build_root.join(b.allocator, &.{ "test", "tools" }) catch @panic("OOM");
        defer b.allocator.free(test_tools);
        run_integration_tests.addPathDir(test_tools);

        const tig_path = exe.getEmittedBin();
        run_integration_tests.addArg("--tig");
        run_integration_tests.addFileArg(tig_path);

        const test_graph_path = test_graph.getEmittedBin();
        run_integration_tests.addArg("--test-graph");
        run_integration_tests.addFileArg(test_graph_path);
    }
    if (b.args) |args| {
        run_integration_tests.addArgs(args);
    }
    const integration_test_step = b.step("integration-test", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);
}

const tig_c_files = [_][]const u8{
    "src/apps.c",
    "src/argv.c",
    "src/blame.c",
    "src/blob.c",
    "src/diff.c",
    "src/display.c",
    "src/draw.c",
    "src/grep.c",
    "src/help.c",
    "src/io.c",
    "src/keys.c",
    "src/line.c",
    "src/log.c",
    "src/main.c",
    "src/map.c",
    "src/options.c",
    "src/pager.c",
    "src/parse.c",
    "src/prompt.c",
    "src/refdb.c",
    "src/reflog.c",
    "src/refs.c",
    "src/repo.c",
    "src/request.c",
    "src/search.c",
    "src/stage.c",
    "src/stash.c",
    "src/status.c",
    "src/string.c",
    "src/tig.c",
    "src/tree.c",
    "src/types.c",
    "src/ui.c",
    "src/util.c",
    "src/view.c",
    "src/watch.c",
};
