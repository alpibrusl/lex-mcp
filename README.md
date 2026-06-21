# lex-mcp

[![CI](https://github.com/alpibrusl/lex-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-mcp/actions/workflows/ci.yml)

**Part of the [Lex](https://lexlang.org) project** — Library · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

> MCP server bridging lex-agent Skills to MCP JSON-RPC — over stdio, HTTP, or
> alongside A2A on one port.

## Transports

A `lex-agent` `AgentDef` defines a capability **once**; lex-mcp exposes it as MCP:

- **stdio** — `mcp.server.run(agent)` (see `examples/echo_agent.lex`). For desktop MCP clients.
- **HTTP** — `http.run_http(agent, port)`. MCP over streamable-HTTP.
- **A2A + MCP on one port** — `compose.serve_both(agent, port)` (see `examples/dual_mount.lex`).
  One process serves the A2A AgentCard + JSON-RPC at `/` and the MCP endpoint at `/mcp`.
  Both transports dispatch through the **same** `srv.dispatch_request`, and `tools/list`
  + the AgentCard derive from the **same** `agent.skills`, so the two surfaces never drift.

## Install

Install the `lex` toolchain: https://github.com/alpibrusl/lex-lang/releases

## Use

Part of the Lex stack. Type-check with `lex check src/*.lex`, run tests with `lex test`, and see `examples/`.
