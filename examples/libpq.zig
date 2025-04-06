const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

const pg = @cImport({
    @cInclude("libpq-fe.h");
});

pub fn main() void {
    const conn = pg.PQconnectdb("postgres://localhost/pgvector_zig_test");
    assert(pg.PQstatus(conn) == pg.CONNECTION_OK);

    var res = pg.PQexec(conn, "CREATE EXTENSION IF NOT EXISTS vector");
    assert(pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK);
    pg.PQclear(res);

    res = pg.PQexec(conn, "DROP TABLE IF EXISTS items");
    assert(pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK);
    pg.PQclear(res);

    res = pg.PQexec(conn, "CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3))");
    assert(pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK);
    pg.PQclear(res);

    const paramValues = [3:0][*c]const u8{ "[1,1,1]", "[2,2,2]", "[1,1,2]" };
    res = pg.PQexecParams(conn, "INSERT INTO items (embedding) VALUES ($1), ($2), ($3)", 3, null, &paramValues, null, null, 0);
    assert(pg.PQresultStatus(res) == pg.PGRES_COMMAND_OK);
    pg.PQclear(res);

    const paramValues2 = [1:0][*c]const u8{"[1,1,1]"};
    res = pg.PQexecParams(conn, "SELECT * FROM items ORDER BY embedding <-> $1 LIMIT 5", 1, null, &paramValues2, null, null, 0);
    assert(pg.PQresultStatus(res) == pg.PGRES_TUPLES_OK);
    const ntuples = pg.PQntuples(res);
    var i: c_int = 0;
    while (i < ntuples) {
        print("{s}: {s}\n", .{ pg.PQgetvalue(res, i, 0), pg.PQgetvalue(res, i, 1) });
        i += 1;
    }
    pg.PQclear(res);

    pg.PQfinish(conn);
}
