# lex-mcp — MCP streamable-HTTP transport
#
# Serves the same JSON-RPC dispatcher (`server.handle_message`) over HTTP instead
# of stdin/stdout, so remote MCP clients (e.g. lex-mcp-client) can reach a lex
# agent's Skills as MCP tools. Stateless: every POST is one JSON-RPC request ->
# one JSON-RPC response; notifications (empty response) return 202.
#
# The entry point is `run_http(agent, port)`. Single endpoint — any POST path is
# treated as the MCP endpoint (clients typically POST to /mcp).

import "std.str" as str

import "std.map" as map

import "std.net" as net

import "lex-agent/src/server" as srv

import "./server" as server

fn mk_resp(status :: Int, body :: Str, hdrs :: Map[Str, Str]) -> Response {
  { status: status, body: BodyStr(body), headers: hdrs }
}

# Serve the MCP dispatcher over HTTP on `port`. Blocks (runs the server loop).
fn run_http(agent :: srv.AgentDef, port :: Int) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  let hdrs := map.from_list([("content-type", "application/json")])
  let handler := fn (req :: Request) -> [io, time, sql, concurrent, net, random, fs_read, fs_write, llm, proc, crypto] Response {
    if req.method == "POST" {
      let out := server.handle_message(agent, req.body)
      if str.is_empty(out) {
        mk_resp(202, "", hdrs)
      } else {
        mk_resp(200, out, hdrs)
      }
    } else {
      mk_resp(405, "{\"error\":\"MCP HTTP transport accepts POST only\"}", hdrs)
    }
  }
  net.serve_fn(port, handler)
}

