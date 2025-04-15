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

    const uri = try std.Uri.parse("https://api.cohere.com/v2/embed");
    const data = .{
        .texts = texts,
        .model = "embed-v4.0",
        .input_type = inputType,
        .embedding_types = [_][]const u8{"ubinary"},
    };

    var authorization = std.ArrayList(u8).init(allocator);
    defer authorization.deinit();
    try authorization.appendSlice("Bearer ");
    try authorization.appendSlice(apiKey);

    var buf: [16 * 1024]u8 = undefined;
    var req = try client.open(.POST, uri, .{ .server_header_buffer = &buf });
    defer req.deinit();
    req.headers = .{
        .authorization = .{ .override = authorization.items },
        .content_type = .{ .override = "application/json" },
    };
    req.transfer_encoding = .chunked;
    try req.send();
    try std.json.stringify(data, .{}, req.writer());
    try req.finish();
    try req.wait();

    std.debug.assert(req.response.status == .ok);
    var rdr = std.json.reader(allocator, req.reader());
    defer rdr.deinit();
    const parsed = try std.json.parseFromTokenSource(Embeddings.EmbedResponse, allocator, &rdr, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    return Embeddings{ .parsed = parsed };
}

fn bitString(allocator: std.mem.Allocator, data: []const u8) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).init(allocator);
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
