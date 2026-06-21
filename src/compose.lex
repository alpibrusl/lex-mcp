# lex-mcp — dual-mount: one AgentDef → A2A + MCP on one port
#
# `serve_both(agent, port)` serves a single `AgentDef` over BOTH transports from
# one process, on one port, by path:
#
#   GET  /.well-known/agent.json   — A2A AgentCard discovery        (lex-agent)
#   POST /                          — A2A JSON-RPC 2.0 dispatch       (lex-agent)
#   POST /mcp                       — MCP streamable-HTTP dispatch     (lex-mcp)
#
# Why this is the base primitive the fleet wants: every service that wants both
# transports otherwise re-wires the plumbing. Here it's a one-liner — and, more
# importantly, BOTH transports dispatch through the SAME `srv.dispatch_request`:
#   - A2A  POST /     → srv.dispatch_request
#   - MCP  POST /mcp  → server.handle_message → tools/call → srv.dispatch_request
# so Skills, effect rows, preconditions, the task store and the audit trail are
# identical no matter which transport a caller arrives on. The MCP `tools/list`
# and the A2A AgentCard both derive from the one `agent.skills` list (via
# `lex-schema`'s `to_json_schema`), so the two surfaces never drift.
#
# This lives in lex-mcp (not lex-agent) on purpose: lex-mcp already depends on
# lex-agent, so combining the two here keeps the dependency edge one-directional.
# Putting it in lex-agent would make lex-agent depend on lex-mcp — a cycle.
#
# serve_both uses only `std.net.serve_fn` (no lex-web router), so it carries no
# dependency beyond what lex-mcp already has. If you're already running a lex-web
# router, keep using `lex-agent`'s `mount.mount` for the A2A routes and add an
# MCP route that calls `server.handle_message` — same dispatch, your middleware.
#
# Run the example:
#   lex run --allow-effects io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc \
#       examples/dual_mount.lex main &
#   curl -s  http://localhost:7777/.well-known/agent.json
#   curl -s -X POST http://localhost:7777/mcp \
#     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
#
# Effects: the server loop's full row (handlers may touch IO, SQL, net, …).

import "std.str" as str

import "std.map" as map

import "std.net" as net

import "lex-agent/src/server" as srv

import "./server" as server

fn mk_resp(status :: Int, body :: Str, hdrs :: Map[Str, Str]) -> Response {
  { status: status, body: BodyStr(body), headers: hdrs }
}

fn json_headers() -> Map[Str, Str] {
  map.from_list([("content-type", "application/json")])
}

fn sse_headers() -> Map[Str, Str] {
  map.from_list([("content-type", "text/event-stream"), ("cache-control", "no-cache"), ("connection", "keep-alive")])
}

# A2A JSON-RPC dispatch (POST /). Mirrors lex-agent's `mount.rpc_route`: the
# HTTP status is always 200 — JSON-RPC errors ride inside the envelope — and a
# `tasks/sendSubscribe` body is answered with SSE frames instead of JSON.
fn a2a_dispatch(agent :: srv.AgentDef, body :: Str) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Response {
  if srv.is_subscribe_body(body) {
    mk_resp(200, srv.dispatch_subscribe_str(agent, body), sse_headers())
  } else {
    mk_resp(200, srv.dispatch_request(agent, body), json_headers())
  }
}

# MCP streamable-HTTP dispatch (POST /mcp). Mirrors lex-mcp's `http.run_http`:
# one POST → one JSON-RPC response; a notification (empty response) returns 202.
fn mcp_dispatch(agent :: srv.AgentDef, body :: Str) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Response {
  let out := server.handle_message(agent, body)
  if str.is_empty(out) {
    mk_resp(202, "", json_headers())
  } else {
    mk_resp(200, out, json_headers())
  }
}

# Serve one AgentDef over A2A + MCP on `port`. Blocks (runs the server loop).
fn serve_both(agent :: srv.AgentDef, port :: Int) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  let handler := fn (req :: Request) -> [io, time, sql, concurrent, net, random, fs_read, fs_write, llm, proc, crypto] Response {
    if req.method == "GET" {
      if req.path == "/.well-known/agent.json" {
        mk_resp(200, srv.agent_card_response(agent), json_headers())
      } else {
        mk_resp(404, "{\"error\":\"not found\"}", json_headers())
      }
    } else {
      if req.method == "POST" {
        if req.path == "/mcp" {
          mcp_dispatch(agent, req.body)
        } else {
          if req.path == "/" {
            a2a_dispatch(agent, req.body)
          } else {
            mk_resp(404, "{\"error\":\"not found\"}", json_headers())
          }
        }
      } else {
        mk_resp(405, "{\"error\":\"method not allowed\"}", json_headers())
      }
    }
  }
  net.serve_fn(port, handler)
}

