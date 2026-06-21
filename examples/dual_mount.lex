# lex-mcp — dual-mount example: one AgentDef, A2A + MCP on one port
#
# The same single-skill `echo` agent as `echo_agent.lex`, but served over BOTH
# transports from one process via `compose.serve_both` — instead of MCP-over-stdio.
# A2A clients hit the AgentCard + JSON-RPC at `/`; MCP clients hit `/mcp`. Both
# arrive at the same `echo_handler` through the same dispatch path.
#
# Run:
#   lex run --allow-effects io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc \
#       examples/dual_mount.lex main &
#
# A2A — discovery + a tasks/send call:
#   curl -s http://localhost:7777/.well-known/agent.json
#   curl -s -X POST http://localhost:7777/ -H 'content-type: application/json' \
#     -d '{"jsonrpc":"2.0","id":1,"method":"tasks/send","params":{
#       "id":"t_1","contextId":"ctx_1",
#       "message":{"kind":"message","messageId":"m1","role":"user",
#                   "parts":[{"type":"text","text":"hi"}]}}}'
#
# MCP — list tools, then call one:
#   curl -s -X POST http://localhost:7777/mcp \
#     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
#   curl -s -X POST http://localhost:7777/mcp \
#     -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
#       "name":"echo","arguments":{"text":"hi"}}}'

import "std.list" as list

import "std.str" as str

import "lex-schema/schema" as sch

import "lex-schema/json_value" as jv

import "lex-spec/capability" as cap

import "lex-agent/src/agent_card" as card

import "lex-agent/src/server" as srv

import "lex-agent/src/message" as msg

import "../src/compose" as compose

# ---- echo capability (same source of truth for A2A card + MCP tools/list) ----
fn echo_capability() -> cap.Capability {
  cap.inbound("echo", "Echo the text argument back to the caller.", { title: "EchoArgs", description: "Input for the echo tool; supply a `text` field.", fields: [sch.required_str("text", [StrNonEmpty])] })
}

fn extract_text(parts :: List[msg.Part]) -> Str {
  list.fold(parts, "", fn (acc :: Str, p :: msg.Part) -> Str {
    if str.is_empty(acc) {
      match p {
        TextPart(s) => s,
        DataPart(j) => match jv.get_field(j, "text") {
          Some(v) => match jv.as_str(v) {
            Some(s) => s,
            None => acc,
          },
          None => acc,
        },
        _ => acc,
      }
    } else {
      acc
    }
  })
}

# The effect row matches `srv.Skill.handle` exactly. (A pure handler is logically
# a subtype, but lex's whole-program check at `lex run` wants the rows to match.)
fn echo_handler(m :: msg.Message) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] srv.HandlerOutcome {
  let reply := msg.agent_text(str.concat("echo: ", extract_text(m.parts)))
  { next_state: TSCompleted, reply: Some(reply), artifacts: [] }
}

fn make_agent() -> srv.AgentDef {
  let agent_card := card.make("echo-dual", "Echo agent served over A2A + MCP on one port.", "0.1.0", "http://localhost:7777", [echo_capability()])
  srv.make_agent_def(agent_card, [{ capability: echo_capability(), handle: echo_handler }])
}

fn main() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  compose.serve_both(make_agent(), 7777)
}

