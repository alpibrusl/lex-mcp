# lex-mcp — Skill → McpTool conversion
#
# Converts lex-agent Skills into MCP tool descriptors. Each Skill
# carries a `Capability` that holds the name, description, and input
# schema (as a `ModelSchema`). We project those onto the McpTool wire
# shape expected by the MCP `tools/list` response.
#
# Pure value module — no effects.

import "std.list" as list

import "lex-schema/schema" as sch

import "lex-agent/src/server" as srv

import "./protocol" as proto

# Convert a single lex-agent Skill to an McpTool.
#
# `skill.capability.name`        → `McpTool.name`
# `skill.capability.description` → `McpTool.description`
# `sch.to_json_schema(skill.capability.params)` → `McpTool.input_schema`
fn skill_to_mcp_tool(skill :: srv.Skill) -> proto.McpTool {
  { name: skill.capability.name, description: skill.capability.description, input_schema: sch.to_json_schema(skill.capability.params) }
}

# Convert all Skills on an AgentDef to a list of McpTools.
fn agent_tools(agent :: srv.AgentDef) -> List[proto.McpTool] {
  list.map(agent.skills, skill_to_mcp_tool)
}

