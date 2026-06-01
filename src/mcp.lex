# lex-mcp — facade re-export
#
# Import this module (as `mcp`) to get the full MCP surface:
#   mcp.protocol.*  — method constants, McpTool type, response builders
#   mcp.tool.*      — skill_to_mcp_tool, agent_tools
#   mcp.server.*    — handle_message, run
#
# Typical usage in an agent binary:
#
#   import "lex-mcp/src/mcp" as mcp
#   fn main() -> [io, ...] Nil {
#     mcp.server.run(my_agent_def)
#   }

import "./protocol" as protocol

import "./tool" as tool

import "./server" as server

type McpTool = tool.McpTool

