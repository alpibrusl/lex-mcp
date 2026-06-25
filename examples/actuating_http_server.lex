# lex-mcp — serving an effectful (e.g. actuating) dispatcher over MCP HTTP.
#
# `run_http(agent, port)` serves a lex-agent `AgentDef`, but `AgentDef`'s
# `Skill.handle` has a fixed effect row that can't carry domain effects like a
# robot's `sense`/`actuate` (alpibrusl/lex-agent#20). For those agents, build
# the JSON-RPC dispatch yourself — reusing lex-mcp's pure `protocol`/`tool`
# builders for the wire format — and serve it with `run_http_fn`, whose
# open effect-row tail `| E` (lex >= 0.10) carries the dispatcher's extra
# effects out to the run-time `--allow-effects` gate.
#
# Here `dispatch` declares `actuate` (standing in for any domain effect the
# generic framework doesn't name). Serving it makes the whole binary require
# `actuate`: withhold it and the server cannot actuate even though the same
# code is reachable over the network — the effect wall holds end to end.
#
# Run:
#   lex run \
#     --allow-effects io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc,actuate \
#     examples/actuating_http_server.lex main
#
#   curl -s localhost:8080 -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'

import "std.str" as str

import "../src/http" as mcphttp

# A minimal effectful dispatcher: takes the raw JSON-RPC body, returns the
# response string ("" would mean a notification → HTTP 202). A real server would
# parse with `lex-agent/src/protocol` and route to `protocol`/`tool` builders;
# this one just echoes a fixed reply and declares the domain effect to show it
# propagating. The `actuate` effect makes this a non-trivial example of the
# row-polymorphic path — a pure `[base]` dispatcher binds `E` to the empty row.
fn dispatch(body :: Str) -> [io, time, sql, concurrent, net, random, fs_read, fs_write, llm, proc, crypto, actuate] Str {
  let _ := body
  str.join(["{\"jsonrpc\":\"2.0\",\"result\":{\"ok\":true}}"], "")
}

fn main() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc, actuate] Nil {
  mcphttp.run_http_fn(8080, dispatch)
}
