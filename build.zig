const std = @import("std");

pub fn build(b: *std.Build) void {
    const pgExe = b.addExecutable(.{
        .name = "pg",
        .root_source_file = b.path("examples/pg.zig"),
        .target = b.graph.host,
    });
    const pg = b.dependency("pg", .{});
    pgExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(pgExe);

    const libpqExe = b.addExecutable(.{
        .name = "libpq",
        .root_source_file = b.path("examples/libpq.zig"),
        .target = b.graph.host,
    });
    libpqExe.linkSystemLibrary("pq");
    libpqExe.linkLibC();
    b.installArtifact(libpqExe);

    const openaiExe = b.addExecutable(.{
        .name = "openai",
        .root_source_file = b.path("examples/openai.zig"),
        .target = b.graph.host,
    });
    openaiExe.root_module.addImport("pg", pg.module("pg"));
    b.installArtifact(openaiExe);
}
