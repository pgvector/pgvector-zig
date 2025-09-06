const pg = @import("pg");
const std = @import("std");

const Embeddings = struct {
    parsed: std.json.Parsed(ApiResponse),

    const ApiResponse = struct {
        embeddings: []const []const f32,
    };

    pub fn deinit(self: *Embeddings) void {
        self.parsed.deinit();
    }

    pub fn get(self: *Embeddings, index: usize) ?[]const f32 {
        const data = self.parsed.value.embeddings;
        return if (index < data.len) data[index] else null;
    }
};

fn embed(allocator: std.mem.Allocator, input: []const []const u8, _: []const u8) !Embeddings {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // TODO nomic-embed-text uses a task prefix
    // https://huggingface.co/nomic-ai/nomic-embed-text-v1.5

    const url = "http://localhost:11434/api/embed";
    const data = .{
        .input = input,
        .model = "nomic-embed-text",
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
    const parsed = try std.json.parseFromSlice(Embeddings.ApiResponse, allocator, body.written(), .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
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
    _ = try conn.exec("CREATE TABLE documents (id bigserial PRIMARY KEY, content text, embedding vector(768))", .{});
    _ = try conn.exec("CREATE INDEX ON documents USING GIN (to_tsvector('english', content))", .{});

    const documents = [_][]const u8{ "The dog is barking", "The cat is purring", "The bear is growling" };
    var documentEmbeddings = try embed(allocator, &documents, "search_document");
    defer documentEmbeddings.deinit();
    for (&documents, 0..) |content, i| {
        const params = .{ content, documentEmbeddings.get(i) };
        _ = try conn.exec("INSERT INTO documents (content, embedding) VALUES ($1, $2::float4[])", params);
    }

    const sql =
        \\WITH semantic_search AS (
        \\    SELECT id, RANK () OVER (ORDER BY embedding <=> $2::float4[]::vector) AS rank
        \\    FROM documents
        \\    ORDER BY embedding <=> $2::float4[]::vector
        \\    LIMIT 20
        \\),
        \\keyword_search AS (
        \\    SELECT id, RANK () OVER (ORDER BY ts_rank_cd(to_tsvector('english', content), query) DESC)
        \\    FROM documents, plainto_tsquery('english', $1) query
        \\    WHERE to_tsvector('english', content) @@ query
        \\    ORDER BY ts_rank_cd(to_tsvector('english', content), query) DESC
        \\    LIMIT 20
        \\)
        \\SELECT
        \\    COALESCE(semantic_search.id, keyword_search.id) AS id,
        \\    COALESCE(1.0 / ($3 + semantic_search.rank), 0.0) +
        \\    COALESCE(1.0 / ($3 + keyword_search.rank), 0.0) AS score
        \\FROM semantic_search
        \\FULL OUTER JOIN keyword_search ON semantic_search.id = keyword_search.id
        \\ORDER BY score DESC
        \\LIMIT 5
    ;

    const query = "growling bear";
    var queryEmbeddings = try embed(allocator, &[_][]const u8{query}, "search_query");
    const k = 60;
    defer queryEmbeddings.deinit();
    var result = try conn.query(sql, .{ query, queryEmbeddings.get(0), k });
    defer result.deinit();
    while (try result.next()) |row| {
        const id = row.get(i64, 0);
        const score = row.get(f64, 1);
        std.debug.print("document: {d} | RRF score: {d}\n", .{ id, score });
    }
}
