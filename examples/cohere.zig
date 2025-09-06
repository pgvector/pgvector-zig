const pg = @import("pg");
const std = @import("std");

const Embeddings = struct {
    parsed: std.json.Parsed(EmbedResponse),

    const EmbeddingsObject = struct {
        ubinary: []const []const u8,
    };

    const EmbedResponse = struct {
        embeddings: EmbeddingsObject,
    };

    pub fn deinit(self: *Embeddings) void {
        self.parsed.deinit();
    }

    pub fn get(self: *Embeddings, index: usize) ?[]const u8 {
        const data = self.parsed.value.embeddings.ubinary;
        return if (index < data.len) data[index] else null;
    }
};

fn embed(allocator: std.mem.Allocator, texts: []const []const u8, inputType: []const u8, apiKey: []const u8) !Embeddings {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const url = "https://api.cohere.com/v2/embed";
    const data = .{
        .texts = texts,
        .model = "embed-v4.0",
        .input_type = inputType,
        .embedding_types = [_][]const u8{"ubinary"},
    };

    var authorization = std.array_list.Managed(u8).init(allocator);
    defer authorization.deinit();
    try authorization.appendSlice("Bearer ");
    try authorization.appendSlice(apiKey);

    const payload = try std.json.Stringify.valueAlloc(allocator, data, .{});
    defer allocator.free(payload);

    var body: std.Io.Writer.Allocating = .init(allocator);
    defer body.deinit();

    const response = try client.fetch(.{
        .method = .POST,
        .location = .{ .url = url },
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = authorization.items },
            .content_type = .{ .override = "application/json" },
        },
        .response_writer = &body.writer,
    });

    std.debug.assert(response.status == .ok);
    const parsed = try std.json.parseFromSlice(Embeddings.EmbedResponse, allocator, body.written(), .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    return Embeddings{ .parsed = parsed };
}

fn bitString(allocator: std.mem.Allocator, data: []const u8) !std.array_list.Managed(u8) {
    var buf = std.array_list.Managed(u8).init(allocator);
    for (data) |v| {
        try buf.writer().print("{b:08}", .{v});
    }
    return buf;
}

pub fn main() !void {
    const apiKey = std.posix.getenv("CO_API_KEY") orelse {
        std.debug.print("Set CO_API_KEY\n", .{});
        std.process.exit(1);
    };

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
    _ = try conn.exec("CREATE TABLE documents (id bigserial PRIMARY KEY, content text, embedding bit(1536))", .{});

    const documents = [_][]const u8{ "The dog is barking", "The cat is purring", "The bear is growling" };
    var documentEmbeddings = try embed(allocator, &documents, "search_document", apiKey);
    defer documentEmbeddings.deinit();
    for (&documents, 0..) |content, i| {
        var bit = try bitString(allocator, documentEmbeddings.get(i).?);
        defer bit.deinit();
        const params = .{ content, bit.items };
        _ = try conn.exec("INSERT INTO documents (content, embedding) VALUES ($1, $2)", params);
    }

    const query = "forest";
    var queryEmbeddings = try embed(allocator, &[_][]const u8{query}, "search_query", apiKey);
    defer queryEmbeddings.deinit();
    var queryBit = try bitString(allocator, queryEmbeddings.get(0).?);
    defer queryBit.deinit();
    var result = try conn.query("SELECT content FROM documents ORDER BY embedding <~> $1 LIMIT 5", .{queryBit.items});
    defer result.deinit();
    while (try result.next()) |row| {
        const content = row.get([]const u8, 0);
        std.debug.print("{s}\n", .{content});
    }
}
