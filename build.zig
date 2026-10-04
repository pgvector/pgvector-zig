const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pgExe = b.addExecutable(.{
        .name = "pg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/pg.zig"),
            .target = target,
        }),
    });
    const pg = b.dependency("pg", .{});
    pgExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(pgExe);

    const libpqExe = b.addExecutable(.{
        .name = "libpq",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/libpq.zig"),
            .target = target,
        }),
    });
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("examples/libpq.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.linkSystemLibrary("pq", .{});
    libpqExe.root_module.addImport("libpq", translate_c.createModule());
    b.installArtifact(libpqExe);

    const openaiExe = b.addExecutable(.{
        .name = "openai",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/openai.zig"),
            .target = target,
        }),
    });
    openaiExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(openaiExe);

    const cohereExe = b.addExecutable(.{
        .name = "cohere",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/cohere.zig"),
            .target = target,
        }),
    });
    cohereExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(cohereExe);

    const hybridExe = b.addExecutable(.{
        .name = "hybrid",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/hybrid.zig"),
            .target = target,
        }),
    });
    hybridExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(hybridExe);

    const sparseExe = b.addExecutable(.{
        .name = "sparse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/sparse.zig"),
            .target = target,
        }),
    });
    sparseExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(sparseExe);
}
