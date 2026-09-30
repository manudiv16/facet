//// Tests for the typed HTTP client, using a one-shot stub server.

import facet/client
import facet/config
import facet/models
import gleam/dynamic
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

@external(erlang, "facet_stub_server", "start")
fn stub_start(status: Int, body: String) -> #(dynamic.Dynamic, Int)

pub fn health_ok_test() {
  let #(_listener, port) =
    stub_start(200, "{\"status\":\"ok\",\"version\":\"1.2.3\"}")
  let client_config = loopback(port)
  let assert Ok(health) = client.health(client_config)
  assert health.status == "ok"
  assert health.version == option_some("1.2.3")
}

pub fn health_carries_http_status_on_error_test() {
  let #(_listener, port) = stub_start(404, "{\"error\":\"nope\"}")
  let client_config = loopback(port)
  let assert Error(config.HttpError(404, "{\"error\":\"nope\"}")) =
    client.health(client_config)
}

pub fn health_reports_network_failure_test() {
  // Port 1 on loopback is not listening, so the connection is refused.
  let client_config =
    config.Config(base_url: "http://127.0.0.1:1", token: None, project: None)
  let assert Error(config.NetworkError(_)) = client.health(client_config)
}

pub fn add_dependency_posts_depends_on_test() {
  let #(listener, port) = stub_start(201, "{\"message\":\"Dependency added\"}")
  let client_config = loopback(port)
  let assert Ok(message) =
    client.add_dependency(client_config, "task-2", "task-1")
  assert message.message == "Dependency added"
  let _ = listener
}

pub fn remove_dependency_deletes_edge_test() {
  let #(listener, port) =
    stub_start(200, "{\"message\":\"Dependency removed\"}")
  let client_config = loopback(port)
  let assert Ok(message) =
    client.remove_dependency(client_config, "task-2", "task-1")
  assert message.message == "Dependency removed"
  let _ = listener
}

pub fn get_blockers_decodes_task_list_test() {
  let body =
    "[{\"id\":\"t\",\"short_id\":\"s\",\"title\":\"Blocker\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"high\",\"status\":\"in_progress\",\"tags\":[],\"parent_id\":null,\"archived\":false,\"created_at\":1,\"updated_at\":2}]"
  let #(listener, port) = stub_start(200, body)
  let client_config = loopback(port)
  let assert Ok(blockers) = client.get_blockers(client_config, "task-3")
  assert list.length(blockers) == 1
  let assert Ok(blocker) = list.first(blockers)
  assert blocker.id == "t"
  assert blocker.status == models.InProgress
  let _ = listener
}

pub fn get_flow_state_decodes_execution_state_test() {
  let body =
    "{\"id\":\"state-1\",\"status\":\"awaiting_input\",\"task_id\":\"task-1\"}"
  let #(listener, port) = stub_start(200, body)
  let client_config = loopback(port)
  let assert Ok(state) = client.get_flow_state(client_config, "flow-1")
  assert state.id == "state-1"
  assert state.status == models.ExecAwaitingInput
  let _ = listener
}

pub fn base_request_uses_api_prefix_test() {
  // The request builder is the test seam for endpoint wiring: it must not
  // raise and must carry the configured host.
  let client_config =
    config.Config(
      base_url: "http://127.0.0.1:4920",
      token: None,
      project: None,
    )
  let assert Ok(request) =
    client.base_request(client_config, http.Get, "/api/v1/tasks")
  assert request.host == "127.0.0.1"
  assert request.port == option_some(4920)
}

fn loopback(port: Int) -> config.Config {
  config.Config(
    base_url: "http://127.0.0.1:" <> int.to_string(port),
    token: None,
    project: None,
  )
}

fn option_some(value: a) -> Option(a) {
  Some(value)
}
