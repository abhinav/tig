const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zit = b.addObject(.{
        .name = "zit",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/zit.zig" },
    });

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
    });
    tig.step.dependOn(&make_builtin_config.step);
    tig.defineCMacro("SYSCONFDIR", "\"/etc\"");
    tig.defineCMacro("TIG_VERSION", "\"1.2.3-dev\"");
    tig.defineCMacro("UINT16_MAX", "65535");
    tig.defineCMacro("false", "0");
    tig.defineCMacro("true", "1");
    tig.addIncludePath(.{ .path = "." });
    tig.addIncludePath(.{ .path = "compat" });
    tig.addIncludePath(.{ .path = "include" });
    tig.addCSourceFiles(&c_source_files, &.{});
    tig.addCSourceFile(.{ .file = builtin_config, .flags = &.{} });
    tig.linkLibC();

    const exe = b.addExecutable(.{
        .name = "tig",
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    exe.addObject(zit);
    exe.addObject(tig);
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
}

const c_source_files = [_][]const u8{
    "compat/hashtab.c",
    "compat/mkstemps.c",
    "compat/setenv.c",
    "compat/strndup.c",
    "compat/utf8proc.c",
    "compat/wordexp.c",

    "src/apps.c",
    "src/argv.c",
    "src/blame.c",
    "src/blob.c",
    "src/diff.c",
    "src/display.c",
    "src/draw.c",
    "src/graph-v1.c",
    "src/graph-v2.c",
    "src/graph.c",
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
