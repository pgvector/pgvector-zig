# pgvector-zig

[pgvector](https://github.com/pgvector/pgvector) examples for Zig

Supports [libpq](https://www.postgresql.org/docs/current/libpq.html)

[![Build Status](https://github.com/pgvector/pgvector-zig/actions/workflows/build.yml/badge.svg)](https://github.com/pgvector/pgvector-zig/actions)

## Getting Started

Follow the instructions for your database library:

- [libpq](#libpq)

## libpq

Import libpq

```zig
const pg = @cImport({
    @cInclude("libpq-fe.h");
});
```

Enable the extension

```zig
const res = pg.PQexec(conn, "CREATE EXTENSION IF NOT EXISTS vector");
```

Create a table

```zig
const res = pg.PQexec(conn, "CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3))");
```

Insert vectors

```zig
const paramValues = [2:0][*c]const u8 {"[1,2,3]", "[4,5,6]"};
const res = pg.PQexecParams(conn, "INSERT INTO items (embedding) VALUES ($1), ($2)", 2, null, &paramValues, null, null, 0);
```

Get the nearest neighbors

```zig
const paramValues = [1:0][*c]const u8 {"[3,1,2]"};
const res = pg.PQexecParams(conn, "SELECT * FROM items ORDER BY embedding <-> $1 LIMIT 5", 1, null, &paramValues, null, null, 0);
```

Add an approximate index

```zig
const res = pg.PQexec(conn, "CREATE INDEX ON items USING ivfflat (embedding vector_l2_ops) WITH (lists = 100)");
// or
const res = pg.PQexec(conn, "CREATE INDEX ON items USING hnsw (embedding vector_l2_ops)");
```

Use `vector_ip_ops` for inner product and `vector_cosine_ops` for cosine distance

See a [full example](example.zig)

## Contributing

Everyone is encouraged to help improve this project. Here are a few ways you can help:

- [Report bugs](https://github.com/pgvector/pgvector-zig/issues)
- Fix bugs and [submit pull requests](https://github.com/pgvector/pgvector-zig/pulls)
- Write, clarify, or fix documentation
- Suggest or add new features

To get started with development:

```sh
git clone https://github.com/pgvector/pgvector-zig.git
cd pgvector-zig
createdb pgvector_zig_test
zig run example.zig -lc -lpq
```

Specify the path to libpq if needed:

```sh
zig run example.zig -I/opt/homebrew/opt/libpq/include -L/opt/homebrew/opt/libpq/lib -lc -lpq
```
