# lex-mcp — server.lex tests
#
# Covers handle_message's JSON-RPC routing (initialize, tools/list,
# tools/call, unknown method) using a minimal single-skill test agent.
#
# run's stdio read-dispatch loop itself (io.readline()-based, fixed from
# the broken io.read("-")) isn't exercised here — a recursive stdin loop
# isn't something `lex test` can drive without piping real stdin into
# the test process — but was verified manually end-to-end (piping a
# tools/list and a tools/call request through examples/echo_agent.lex's
# main). handle_message is what run wraps per line, and IS what this
# file pins.

import "std.str" as str

import "std.list" as list

import "lex-schema/schema" as sch

import "lex-agent/src/agent_card" as card

import "lex-agent/src/server" as srv

import "lex-agent/src/message" as msg

import "lex-spec/capability" as cap

import "lex-schema/json_value" as jv

import "../src/server" as mcp_srv

# ---- Test scaffolding -----------------------------------------------
fn pass() -> Result[Unit, Str] {
  Ok(())
}

fn fail(why :: Str) -> Result[Unit, Str] {
  Err(why)
}

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    pass()
  } else {
    fail(label)
  }
}

fn assert_contains(haystack :: Str, needle :: Str, label :: Str) -> Result[Unit, Str] {
  assert_true(str.contains(haystack, needle), str.concat(label, str.concat(" (body: ", str.concat(haystack, ")"))))
}

# ---- Minimal test agent (mirrors examples/echo_agent.lex's shape) -----
fn echo_capability() -> cap.Capability {
  cap.inbound("echo", "Echo the text argument back.", { title: "EchoArgs", description: "supply a text field", fields: [sch.required_str("text", [])] })
}

fn extract_text(parts :: List[msg.Part]) -> Str {
  list.fold(parts, "", fn (acc :: Str, p :: msg.Part) -> Str {
    if str.is_empty(acc) {
      match p {
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

fn echo_handler(m :: msg.Message) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] srv.HandlerOutcome {
  let text := extract_text(m.parts)
  { next_state: TSCompleted, reply: Some(msg.agent_text(str.concat("echo: ", text))), artifacts: [] }
}

fn test_agent() -> srv.AgentDef {
  let agent_card := card.make("test-agent", "Test agent.", "0.0.1", "stdio://test-agent", [echo_capability()])
  srv.make_agent_def(agent_card, [{ capability: echo_capability(), handle: echo_handler }])
}

# ---- initialize --------------------------------------------------
fn test_initialize_returns_server_info() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Result[Unit, Str] {
  let resp := mcp_srv.handle_message(test_agent(), "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
  match assert_contains(resp, "\"serverInfo\"", "initialize must return a serverInfo object") {
    Err(e) => Err(e),
    Ok(_) => assert_contains(resp, "\"test-agent\"", "serverInfo must carry the agent's own name"),
  }
}

# ---- tools/list ----------------------------------------------------
fn test_tools_list_returns_the_skill() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Result[Unit, Str] {
  let resp := mcp_srv.handle_message(test_agent(), "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
  assert_contains(resp, "\"echo\"", "tools/list must list the agent's echo skill")
}

# ---- tools/call ------------------------------------------------------
fn test_tools_call_dispatches_to_the_handler() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Result[Unit, Str] {
  let resp := mcp_srv.handle_message(test_agent(), "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"echo\",\"arguments\":{\"text\":\"hi\"}}}")
  assert_contains(resp, "echo: hi", "tools/call must dispatch to echo_handler and carry its reply text")
}

fn test_tools_call_missing_name_is_an_error() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Result[Unit, Str] {
  let resp := mcp_srv.handle_message(test_agent(), "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{}}")
  assert_contains(resp, "missing required param", "tools/call with no `name` must report the missing-param error, not silently no-op")
}

# ---- Unknown method ---------------------------------------------------
fn test_unknown_method_is_method_not_found() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Result[Unit, Str] {
  let resp := mcp_srv.handle_message(test_agent(), "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"bogus/method\",\"params\":{}}")
  match assert_contains(resp, "\"error\"", "an unrecognized method must be a JSON-RPC error") {
    Err(e) => Err(e),
    Ok(_) => assert_contains(resp, "-32601", "the error code must be the standard method-not-found (-32601)"),
  }
}

# ---- Malformed request --------------------------------------------
fn test_malformed_json_is_a_parse_error() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Result[Unit, Str] {
  let resp := mcp_srv.handle_message(test_agent(), "not json at all")
  assert_contains(resp, "\"error\"", "unparseable input must produce a JSON-RPC error response, not crash the loop")
}

# ---- Suite + runner ---------------------------------------------------
fn suite() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] List[Result[Unit, Str]] {
  [test_initialize_returns_server_info(), test_tools_list_returns_the_skill(), test_tools_call_dispatches_to_the_handler(), test_tools_call_missing_name_is_an_error(), test_unknown_method_is_method_not_found(), test_malformed_json_is_a_parse_error()]
}

fn count_failures(rs :: List[Result[Unit, Str]]) -> Int {
  list.fold(rs, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
}

fn run_all() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Int {
  count_failures(suite())
}

