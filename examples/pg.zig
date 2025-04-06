const pg = @import("pg");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var pool = try pg.Pool.init(allocator, .{ .auth = .{
        .username = std.posix.getenv("USER").?,
        .database = "pgvector_zig_test",
    } });
    defer pool.deinit();

    const conn = try pool.acquire();
    defer pool.release(conn);

    _ = try conn.exec("CREATE EXTENSION IF NOT EXISTS vector", .{});

    _ = try conn.exec("DROP TABLE IF EXISTS pg_items", .{});

    _ = try conn.exec("CREATE TABLE pg_items (id bigserial PRIMARY KEY, embedding vector(3))", .{});

    const params = .{ [_]f32{ 1, 1, 1 }, [_]f32{ 2, 2, 2 }, [_]f32{ 1, 1, 2 } };
    _ = try conn.exec("INSERT INTO pg_items (embedding) VALUES ($1::float4[]), ($2::float4[]), ($3::float4[])", params);

    const queryParams = .{[_]f32{ 3, 1, 2 }};
    var result = try conn.query("SELECT id FROM pg_items ORDER BY embedding <-> $1::float4[]::vector LIMIT 5", queryParams);
    defer result.deinit();
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        std.debug.print("{d}\n", .{id});
    }
}
