# lex-mcp — MCP stdio server
#
# Reads newline-delimited JSON-RPC 2.0 messages from stdin, routes
# them to lex-agent Skills, and writes JSON-RPC responses back to
# stdout — the stdio transport defined by the MCP spec.
#
# The entry point is `run(agent)`. It loops until stdin closes (EOF
# surfaces as `Err` from `io.read`).
#
# Method routing:
#   initialize              → MCP handshake (protocolVersion + serverInfo)
#   notifications/initialized → notification; no response emitted
#   tools/list              → enumerate all Skills as McpTools
#   tools/call              → dispatch via srv.dispatch_request (A2A tasks/send)
#   anything else           → JSON-RPC -32601 method-not-found

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "lex-schema/json_value" as jv

import "lex-agent/src/protocol" as rpc

import "lex-agent/src/server" as srv

import "./protocol" as proto

import "./tool" as tool

# ---- Synthetic tasks/send body builder ---------------------------
#
# MCP tools/call params: { name: "skill_name", arguments: { ... } }
#
# We build a minimal A2A tasks/send body. The `message` carries the
# arguments as a DataPart so the handler can inspect them. The `skill`
# extension field routes dispatch to the right handler.
fn build_tasks_send_body(rpc_id :: rpc.RpcId, skill_name :: Str, arguments :: jv.Json) -> Str {
  let id_json := match rpc_id {
    IdInt(n) => JInt(n),
    IdStr(s) => JStr(s),
    IdNull => JStr("mcp_null"),
  }
  let message_obj := JObj([("kind", JStr("message")), ("messageId", JStr("mcp_args")), ("role", JStr("user")), ("parts", JList([JObj([("type", JStr("data")), ("data", arguments)])]))])
  let params := JObj([("id", JStr("mcp_task")), ("contextId", JStr("mcp_ctx")), ("message", message_obj), ("skill", JStr(skill_name))])
  let req := JObj([("jsonrpc", JStr("2.0")), ("id", id_json), ("method", JStr("tasks/send")), ("params", params)])
  jv.stringify(req)
}

# ---- Extract reply text from A2A dispatch_request response -------
#
# `dispatch_request` returns a JSON-RPC response string. On success
# the result is a Task JSON object. We try to extract the text from:
#   result.status.message.parts[0].text
# Falling back to the full result JSON stringified if unavailable.
fn extract_reply_text(dispatch_response :: Str) -> Str {
  match jv.parse(dispatch_response) {
    Err(_) => dispatch_response,
    Ok(j) => match jv.get_field(j, "result") {
      None => match jv.get_field(j, "error") {
        None => dispatch_response,
        Some(e) => match jv.get_field(e, "message") {
          None => dispatch_response,
          Some(m) => match jv.as_str(m) {
            Some(s) => s,
            None => dispatch_response,
          },
        },
      },
      Some(result) => match jv.get_field(result, "status") {
        None => jv.stringify(result),
        Some(status) => match jv.get_field(status, "message") {
          None => jv.stringify(result),
          Some(msg_j) => match jv.get_field(msg_j, "parts") {
            None => jv.stringify(result),
            Some(pj) => match jv.as_list(pj) {
              None => jv.stringify(result),
              Some(parts) => match list.head(parts) {
                None => jv.stringify(result),
                Some(p) => match jv.get_field(p, "text") {
                  None => jv.stringify(result),
                  Some(tv) => match jv.as_str(tv) {
                    Some(t) => t,
                    None => jv.stringify(result),
                  },
                },
              },
            },
          },
        },
      },
    },
  }
}

# ---- Per-message handler -----------------------------------------
fn handle_message(agent :: srv.AgentDef, body :: Str) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Str {
  match rpc.parse_request(body) {
    Err(rpcerr) => rpc.response_to_str(ResErr(IdNull, rpcerr)),
    Ok(req) => route(agent, req),
  }
}

fn route(agent :: srv.AgentDef, req :: rpc.Request) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Str {
  if req.method == proto.method_initialize() {
    let result := proto.initialize_result(agent.card.name, agent.card.version)
    rpc.response_to_str(ResOk(req.id, result))
  } else {
    if req.method == proto.method_notifications_initialized() {
      ""
    } else {
      if req.method == proto.method_tools_list() {
        let tools := tool.agent_tools(agent)
        let result := proto.tools_list_result(tools)
        rpc.response_to_str(ResOk(req.id, result))
      } else {
        if req.method == proto.method_tools_call() {
          handle_tools_call(agent, req)
        } else {
          rpc.response_to_str(ResErr(req.id, { code: proto.err_method_not_found(), message: str.concat("method not supported: ", req.method), data: None }))
        }
      }
    }
  }
}

fn handle_tools_call(agent :: srv.AgentDef, req :: rpc.Request) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Str {
  let params := req.params
  let skill_name := match jv.get_field(params, "name") {
    None => "",
    Some(v) => match jv.as_str(v) {
      Some(s) => s,
      None => "",
    },
  }
  let arguments := match jv.get_field(params, "arguments") {
    None => JObj([]),
    Some(a) => a,
  }
  if str.is_empty(skill_name) {
    let result := proto.tools_call_error("tools/call missing required param: name")
    rpc.response_to_str(ResOk(req.id, result))
  } else {
    let body := build_tasks_send_body(req.id, skill_name, arguments)
    let dispatch_resp := srv.dispatch_request(agent, body)
    let reply_text := extract_reply_text(dispatch_resp)
    let is_err := str.contains(dispatch_resp, "\"error\"")
    let result := if is_err {
      proto.tools_call_error(reply_text)
    } else {
      proto.tools_call_result(reply_text)
    }
    rpc.response_to_str(ResOk(req.id, result))
  }
}

# ---- stdio read-dispatch loop ------------------------------------
fn run(agent :: srv.AgentDef) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Nil {
  match io.read("-") {
    Err(_) => (),
    Ok(line) => {
      let trimmed := str.trim(line)
      let response := if str.is_empty(trimmed) {
        ""
      } else {
        handle_message(agent, trimmed)
      }
      let __out := if str.is_empty(response) {
        ()
      } else {
        io.print(response)
      }
      run(agent)
    },
  }
}

