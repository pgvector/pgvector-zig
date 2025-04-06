const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example.zig"),
        .target = b.graph.host,
    });

    exe.linkSystemLibrary("pq");
    exe.linkLibC();

    b.installArtifact(exe);
}
