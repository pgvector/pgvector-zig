// good resources
// https://opensearch.org/blog/improving-document-retrieval-with-sparse-semantic-encoders/
// https://huggingface.co/opensearch-project/opensearch-neural-sparse-encoding-v1
//
// run with
// text-embeddings-router --model-id opensearch-project/opensearch-neural-sparse-encoding-v1 --pooling splade

const pg = @import("pg");
const std = @import("std");

const Embeddings = struct {
    parsed: std.json.Parsed([]const []const f32),

    pub fn deinit(self: *Embeddings) void {
        self.parsed.deinit();
    }

    pub fn get(self: *Embeddings, index: usize) ?[]const f32 {
        const data = self.parsed.value;
        return if (index < data.len) data[index] else null;
    }
};

fn embed(allocator: std.mem.Allocator, inputs: []const []const u8) !Embeddings {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = "http://localhost:3000/embed";
    const data = .{
        .inputs = inputs,
        .normalize = false,
    };

    const payload = try std.json.Stringify.valueAlloc(allocator, data, .{});
    defer allocator.free(payload);

    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();

    const response = try client.fetch(.{
        .method = .POST,
        .location = .{ .url = url },
        .payload = payload,
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
        .response_writer = &body.writer,
    });

    std.debug.assert(response.status == .ok);
    const parsed = try std.json.parseFromSlice([]const []const f32, allocator, body.written(), .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    return Embeddings{ .parsed = parsed };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var pool = try pg.Pool.init(allocator, .{ .auth = .{
        .username = std.posix.getenv("USER").?,
        .database = "pgvector_example",
    } });
    defer pool.deinit();

    const conn = try pool.acquire();
    defer pool.release(conn);

    _ = try conn.exec("CREATE EXTENSION IF NOT EXISTS vector", .{});
    _ = try conn.exec("DROP TABLE IF EXISTS documents", .{});
    _ = try conn.exec("CREATE TABLE documents (id bigserial PRIMARY KEY, content text, embedding sparsevec(30522))", .{});

    const documents = [_][]const u8{ "The dog is barking", "The cat is purring", "The bear is growling" };
    var documentEmbeddings = try embed(allocator, &documents);
    defer documentEmbeddings.deinit();
    for (&documents, 0..) |content, i| {
        const params = .{ content, documentEmbeddings.get(i) };
        _ = try conn.exec("INSERT INTO documents (content, embedding) VALUES ($1, $2::float4[])", params);
    }

    const query = "forest";
    var queryEmbeddings = try embed(allocator, &[_][]const u8{query});
    defer queryEmbeddings.deinit();
    var result = try conn.query("SELECT content FROM documents ORDER BY embedding <#> $1::float4[]::sparsevec LIMIT 5", .{queryEmbeddings.get(0)});
    defer result.deinit();
    while (try result.next()) |row| {
        const content = row.get([]const u8, 0);
        std.debug.print("{s}\n", .{content});
    }
}
