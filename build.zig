const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compat = b.addStaticLibrary(.{
        .name = "compat",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    compat.addIncludePath(b.path("compat"));
    compat.addCSourceFiles(.{ .files = &.{
        "compat/hashtab.c",
        "compat/mkstemps.c",
        "compat/setenv.c",
        "compat/strndup.c",
        "compat/utf8proc.c",
        "compat/wordexp.c",
    } });

    const graph = b.addStaticLibrary(.{
        .name = "graph",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    graph.addIncludePath(b.path("."));
    graph.addIncludePath(b.path("include"));
    graph.addCSourceFiles(.{ .files = &.{
        "src/graph-v1.c",
        "src/graph-v2.c",
        "src/graph.c",
    } });

    const zit = b.addStaticLibrary(.{
        .name = "zit",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zit.zig"),
        .link_libc = true,
    });
    zit.addIncludePath(b.path("."));
    zit.addIncludePath(b.path("include"));
    // TODO: Use zit.getEmittedH, and then dirname of that
    // (https://github.com/ziglang/zig/issues/17411).

    const make_builtin_config = b.addSystemCommand(&.{"./tools/make-builtin-config.sh"});
    make_builtin_config.addFileArg(b.path("tigrc"));
    // Hack: captureStdOut does not allow specifying the name of the file.
    // As a workaround, change the configuration of the Output object
    // after having captureStdOut wire it up.
    const builtin_config = make_builtin_config.captureStdOut();
    make_builtin_config.captured_stdout.?.basename = "builtin-config.c";

    const tig = b.addStaticLibrary(.{
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
    tig.addIncludePath(b.path("."));
    tig.addIncludePath(b.path("include"));
    tig.addCSourceFiles(.{ .files = &tig_c_files });
    tig.addCSourceFile(.{ .file = builtin_config, .flags = &.{} });

    const exe = b.addExecutable(.{
        .name = "tig",
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
    });
    exe.linkLibrary(zit);
    exe.linkLibrary(tig);
    exe.linkLibrary(compat);
    exe.linkLibrary(graph);
    exe.linkSystemLibrary("ncursesw");
    exe.linkSystemLibrary("iconv");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/zit.zig"),
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
    test_graph.addIncludePath(b.path("."));
    test_graph.addIncludePath(b.path("include"));
    test_graph.addCSourceFiles(.{ .files = &.{
        "test/tools/test-graph.c",
        "src/string.c",
        "src/util.c",
        "src/io.c",
    } });
    test_graph.linkLibrary(compat);
    test_graph.linkLibrary(graph);
    test_graph.linkSystemLibrary("ncursesw");
    test_graph.linkSystemLibrary("iconv");

    const integration_tests = b.addExecutable(.{
        .name = "integration-test-runner",
        .root_source_file = b.path("test/integration.zig"),
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
