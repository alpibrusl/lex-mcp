# lex-mcp — MCP JSON-RPC 2.0 protocol types and builders
#
# The Model Context Protocol (MCP) rides JSON-RPC 2.0, just like A2A.
# This module defines:
#
#   - MCP method name constants
#   - `McpTool` — the wire shape for a single tool advertisement
#   - Response builders: `initialize_result`, `tools_list_result`,
#     `tools_call_result`, `tools_call_error`
#
# Wire shape follows MCP spec 2024-11-05.
#
# Pure value module — no effects.

import "std.list" as list

import "std.str" as str

import "lex-schema/json_value" as jv

import "lex-agent/src/protocol" as rpc

# ---- MCP method constants ----------------------------------------
fn method_initialize() -> Str {
  "initialize"
}

fn method_tools_list() -> Str {
  "tools/list"
}

fn method_tools_call() -> Str {
  "tools/call"
}

fn method_notifications_initialized() -> Str {
  "notifications/initialized"
}

# ---- McpTool -------------------------------------------------------
#
# Represents a single MCP tool as advertised in `tools/list`.
# `input_schema` is a JSON Schema object (from `sch.to_json_schema`).
type McpTool = { name :: Str, description :: Str, input_schema :: jv.Json }

fn mcp_tool_to_json(t :: McpTool) -> jv.Json {
  JObj([("name", JStr(t.name)), ("description", JStr(t.description)), ("inputSchema", t.input_schema)])
}

# ---- initialize result -------------------------------------------
#
# Returns the MCP initialize handshake result object.
# The client sends `initialize`; we respond with protocol version,
# server info, and a `capabilities` map advertising `tools`.
fn initialize_result(name :: Str, version :: Str) -> jv.Json {
  JObj([("protocolVersion", JStr("2024-11-05")), ("capabilities", JObj([("tools", JObj([]))])), ("serverInfo", JObj([("name", JStr(name)), ("version", JStr(version))]))])
}

# ---- tools/list result -------------------------------------------
fn tools_list_result(tools :: List[McpTool]) -> jv.Json {
  JObj([("tools", JList(list.map(tools, mcp_tool_to_json)))])
}

# ---- tools/call result -------------------------------------------
#
# MCP tools/call result shape:
#   { "content": [ { "type": "text", "text": "..." } ], "isError": false }
fn tools_call_result(text :: Str) -> jv.Json {
  JObj([("content", JList([JObj([("type", JStr("text")), ("text", JStr(text))])])), ("isError", JBool(false))])
}

fn tools_call_error(text :: Str) -> jv.Json {
  JObj([("content", JList([JObj([("type", JStr("text")), ("text", JStr(text))])])), ("isError", JBool(true))])
}

# ---- JSON-RPC error helpers (re-exported for server convenience) --
fn err_method_not_found() -> Int {
  rpc.err_method_not_found()
}

fn err_internal() -> Int {
  rpc.err_internal()
}

