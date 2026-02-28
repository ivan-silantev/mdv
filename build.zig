const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const renderer_module = b.createModule(.{
        .root_source_file = b.path("src/renderer.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Define modules for the new refactored files
    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const platform_module = b.createModule(.{
        .root_source_file = b.path("src/platform.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "mdv_renderer",
        .root_module = renderer_module,
    });
    lib.installHeader(b.path("include/mdv_renderer.h"), "mdv_renderer.h");

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const printing_module = b.createModule(.{
        .root_source_file = b.path("src/printing.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_module.addImport("mdv_renderer", renderer_module);
    exe_module.addImport("cli", cli_module);
    exe_module.addImport("platform", platform_module);
    exe_module.addImport("printing", printing_module);
    platform_module.addImport("mdv_renderer", renderer_module);
    printing_module.addImport("mdv_renderer", renderer_module);

    const exe = b.addExecutable(.{
        .name = "mdv",
        .root_module = exe_module,
    });

    b.installArtifact(lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const renderer_unit_tests = b.addTest(.{
        .root_module = renderer_module,
    });
    const run_renderer_unit_tests = b.addRunArtifact(renderer_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_module,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_renderer_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
