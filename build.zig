const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("carnaval", .{
        .root_source_file = b.path("lib/carnaval/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const lib = b.addLibrary(.{
        .name = "carnaval",
        .root_module = lib_mod,
    });

    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate the documentation");
    docs_step.dependOn(&docs.step);

    const tests_step = b.step("test", "Run the test suite");

    const integration_tests = b.addTest(.{
        .name = "Integration",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/suite.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{
                .name = "carnaval",
                .module = lib_mod,
            }},
        }),
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    tests_step.dependOn(&run_integration_tests.step);

    const unit_tests = b.addTest(.{
        .name = "Unit",
        .root_module = lib_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    tests_step.dependOn(&run_unit_tests.step);

    const check_step = b.step("check", "Run code quality checks");

    const fmt = b.addFmt(.{
        .check = true,
        .paths = &.{"lib/"},
    });
    check_step.dependOn(&fmt.step);
}
