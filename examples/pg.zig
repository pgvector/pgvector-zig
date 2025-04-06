const pg = @import("pg");
const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    var pool = try pg.Pool.init(allocator, .{ .auth = .{
        .username = std.mem.sliceTo(std.posix.getenv("USER").?, 0),
        .database = "pgvector_zig_test",
    } });
    defer pool.deinit();

    const conn = try pool.acquire();
    defer pool.release(conn);

    _ = try conn.exec("CREATE EXTENSION IF NOT EXISTS vector", .{});

    _ = try conn.exec("DROP TABLE IF EXISTS pg_items", .{});

    _ = try conn.exec("CREATE TABLE pg_items (id bigserial PRIMARY KEY, embedding vector(3))", .{});

    const params = .{ "[1,1,1]", "[2,2,2]", "[1,1,2]" };
    _ = try conn.exec("INSERT INTO pg_items (embedding) VALUES ($1), ($2), ($3)", params);

    var result = try conn.query("SELECT id FROM pg_items ORDER BY embedding <-> $1 LIMIT 5", .{"[1,1,1]"});
    defer result.deinit();
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        print("{d}\n", .{id});
    }
}
