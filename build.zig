const std = @import("std");

pub fn build(b: *std.Build) void {
    const libpqExe = b.addExecutable(.{
        .name = "libpq",
        .root_source_file = b.path("examples/libpq.zig"),
        .target = b.graph.host,
    });
    libpqExe.linkSystemLibrary("pq");
    libpqExe.linkLibC();
    b.installArtifact(libpqExe);
}
