# lex-mcp — echo agent example
#
# Minimal end-to-end demonstration: a single-skill agent exposed as an
# MCP server over stdio. Point Claude Desktop (or any MCP client) at
# this binary and it will advertise one tool — `echo` — that returns
# the text it receives.
#
# Run:
#   lex run --allow-effects io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc \
#       examples/echo_agent.lex main
#
# Claude Desktop config (~/Library/Application Support/Claude/claude_desktop_config.json):
#   {
#     "mcpServers": {
#       "echo": {
#         "command": "lex",
#         "args": ["run", "--allow-effects", "io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc",
#                  "/path/to/lex-mcp/examples/echo_agent.lex", "main"]
#       }
#     }
#   }

import "std.list" as list

import "std.str" as str

import "lex-schema/schema" as sch

import "lex-schema/constraints" as c

import "lex-schema/json_value" as jv

import "lex-spec/capability" as cap

import "lex-agent/src/agent_card" as card

import "lex-agent/src/server" as srv

import "lex-agent/src/message" as msg

import "lex-agent/src/task" as tk

import "../src/mcp" as mcp

# ---- echo capability ---------------------------------------------
fn echo_capability() -> cap.Capability {
  cap.inbound("echo", "Echo the text argument back to the caller.", { title: "EchoArgs", description: "Input for the echo tool; supply a `text` field.", fields: [sch.required_str("text", [StrNonEmpty])] })
}

# ---- echo handler ------------------------------------------------
#
# Extracts the `text` field from the DataPart arguments object passed
# by the MCP adapter (tools/call arguments arrive as DataPart JSON),
# or falls back to the first TextPart if present.
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

fn echo_handler(m :: msg.Message) -> srv.HandlerOutcome {
  let text := extract_text(m.parts)
  let reply := msg.agent_text(str.concat("echo: ", text))
  { next_state: TSCompleted, reply: Some(reply), artifacts: [] }
}

# ---- Agent assembly ----------------------------------------------
fn make_agent() -> srv.AgentDef {
  let agent_card := card.make("echo-mcp", "Minimal echo agent exposed over MCP stdio.", "0.1.0", "stdio://echo-mcp", [echo_capability()])
  srv.make_agent_def(agent_card, [{ capability: echo_capability(), handle: echo_handler }])
}

# ---- Entry point -------------------------------------------------
fn main() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  mcp.server.run(make_agent())
}

