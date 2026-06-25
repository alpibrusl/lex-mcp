# lex-mcp — MCP streamable-HTTP transport
#
# Serves a JSON-RPC dispatcher over HTTP instead of stdin/stdout, so remote MCP
# clients (e.g. lex-mcp-client) can reach a lex agent's Skills as MCP tools.
# Stateless: every POST is one JSON-RPC request -> one JSON-RPC response;
# notifications (empty response) return 202.
#
# Two entry points:
#
#   run_http(agent, port)        — serve a lex-agent `AgentDef`'s Skills. The
#                                  handler effects are exactly lex-agent's fixed
#                                  Skill.handle row (no `sense`/`actuate`).
#
#   run_http_fn[E](port, dispatch) — serve an arbitrary `(body) -> [base | E]
#                                  String` dispatcher. The open effect-row tail
#                                  `E` (lex >= 0.10) lets the caller's dispatcher
#                                  declare DOMAIN effects the generic framework
#                                  doesn't name — e.g. a robot agent's `actuate`
#                                  — and have them flow out to `run_http_fn`'s own
#                                  row, so `lex run --allow-effects` still gates
#                                  them. This is the path for agents whose
#                                  handlers can't fit lex-agent's fixed
#                                  `Skill.handle` row (alpibrusl/lex-agent#20):
#                                  build the JSON-RPC dispatch yourself (reusing
#                                  lex-mcp's pure `protocol`/`tool` builders) and
#                                  hand it here.
#
# `run_http` is a thin wrapper over `run_http_fn` with `E` bound to the empty
# row, so both share one transport loop.

import "std.str" as str

import "std.map" as map

import "std.net" as net

import "lex-agent/src/server" as srv

import "./server" as server

fn mk_resp(status :: Int, body :: Str, hdrs :: Map[Str, Str]) -> Response {
  { status: status, body: BodyStr(body), headers: hdrs }
}

# Serve an arbitrary JSON-RPC `dispatch` (body string -> response string, "" for
# a notification) over HTTP on `port`. Row-polymorphic over the dispatcher's
# extra effects `E`: pass a pure `[base]` dispatcher and `E` is empty; pass one
# that also declares `[base, sense, actuate]` and the whole server requires
# `actuate` at run time. Blocks (runs the server loop).
fn run_http_fn[E](port :: Int, dispatch :: (Str) -> [io, time, sql, concurrent, net, random, fs_read, fs_write, llm, proc, crypto | E] Str) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc | E] Nil {
  let hdrs := map.from_list([("content-type", "application/json")])
  let handler := fn (req :: Request) -> [io, time, sql, concurrent, net, random, fs_read, fs_write, llm, proc, crypto | E] Response {
    if req.method == "POST" {
      let out := dispatch(req.body)
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

# Serve a lex-agent `AgentDef`'s Skills as MCP tools over HTTP. Thin wrapper over
# `run_http_fn`: the dispatcher is `server.handle_message`, whose effects are
# lex-agent's fixed Skill.handle row, so `E` unifies to the empty row and this
# signature stays closed (unchanged from pre-0.10).
fn run_http(agent :: srv.AgentDef, port :: Int) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  run_http_fn(port, fn (body :: Str) -> [io, time, sql, concurrent, net, random, fs_read, fs_write, llm, proc, crypto] Str {
    server.handle_message(agent, body)
  })
}

