const std = @import("std");
const project_version = std.mem.trimRight(u8, @embedFile("VERSION"), "\r\n");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "Version string embedded in the binary") orelse project_version;

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const exe = b.addExecutable(.{
        .name = "sloc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);
    b.installFile("LICENSE", "share/licenses/sloc/LICENSE");
    b.installFile("README.md", "share/doc/sloc/README.md");
    b.installFile("CHANGELOG.md", "share/doc/sloc/CHANGELOG.md");
    b.installFile("docs/sloc.1", "share/man/man1/sloc.1");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run sloc");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
