const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const carnaval_mod = b.addModule("carnaval", .{
        .root_source_file = b.path("lib/carnaval/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const carnaval_mod_lib = b.addLibrary(.{
        .name = "carnaval",
        .root_module = carnaval_mod,
    });

    const carnaval_docs = b.addInstallDirectory(.{
        .source_dir = carnaval_mod_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate the documentation");
    docs_step.dependOn(&carnaval_docs.step);

    const tests_step = b.step("test", "Run the test suite");

    const integration_tests = b.addTest(.{
        .name = "Integration",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/suite.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{
                .name = "carnaval",
                .module = carnaval_mod,
            }},
        }),
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    tests_step.dependOn(&run_integration_tests.step);

    const carnaval_mod_lib_tests = b.addTest(.{
        .name = "Carnaval",
        .root_module = carnaval_mod,
    });

    const run_carnaval_mod_lib_tests = b.addRunArtifact(carnaval_mod_lib_tests);
    tests_step.dependOn(&run_carnaval_mod_lib_tests.step);

    const check_step = b.step("check", "Run code quality checks");

    const fmt = b.addFmt(.{
        .check = true,
        .paths = &.{"lib/"},
    });
    check_step.dependOn(&fmt.step);
}
