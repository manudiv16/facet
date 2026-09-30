//// End-to-end CLI tests: every command is dispatched against a one-shot stub
//// server, and the captured request asserts the exact method, path and body
//// the client sends. This is the "every command correct vs running
//// instance" acceptance criterion, pinned down in code.

import facet/cli/app
import facet/cli/commands
import facet/cli/types
import facet/config
import facet/models
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/option.{None, Some}

@external(erlang, "facet_stub_server", "start_capture")
fn stub_start_capture(
  status: Int,
  body: String,
) -> #(dynamic.Dynamic, Int, dynamic.Dynamic)

@external(erlang, "facet_stub_server", "get_captured")
fn stub_get_captured(collector: dynamic.Dynamic) -> dynamic.Dynamic

// ─── Wire-format fixtures ───────────────────────────────────────────────────

const task_json = "{\"id\":\"task-1\",\"short_id\":\"00000001\",\"title\":\"T\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"medium\",\"status\":\"todo\",\"tags\":[],\"parent_id\":null,\"archived\":false,\"created_at\":1,\"updated_at\":2}"

const blocked_task_json = "{\"id\":\"task-2\",\"short_id\":\"00000002\",\"title\":\"Dependent\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"low\",\"status\":\"blocked\",\"tags\":[],\"parent_id\":null,\"archived\":false,\"created_at\":1,\"updated_at\":2}"

const template_json = "{\"id\":\"linear\",\"name\":\"Linear\",\"description\":\"\",\"nodes\":{},\"transitions\":[],\"initial_node_id\":\"n1\"}"

const instance_json = "{\"id\":\"flow-1\",\"template_id\":\"linear\",\"task_id\":\"task-1\",\"nodes\":{},\"transitions\":[],\"initial_node_id\":\"n1\"}"

const state_json = "{\"id\":\"state-1\",\"status\":\"running\",\"task_id\":\"task-1\"}"

const step_json = "{\"id\":\"step-1\",\"status\":\"completed\",\"node_id\":\"n1\",\"task_id\":\"task-1\"}"

const run_step_action_json = "{\"kind\":\"run_step\",\"node\":{\"id\":\"n1\",\"name\":\"Research\",\"node_type\":\"step\"},\"prompt\":\"do it\"}"

const log_json = "{\"id\":\"log-1\",\"event_type\":\"text\",\"payload\":\"{}\",\"sequence\":1}"

const section_json = "{\"id\":\"sec-1\",\"task_id\":\"task-1\",\"section_type\":\"goal\",\"content\":\"Ship the release\",\"order\":1}"

// ─── health ─────────────────────────────────────────────────────────────────

pub fn health_hits_health_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "{\"status\":\"ok\",\"version\":\"1.2.3\"}")
  let config = loopback(port)
  let assert Ok(types.HealthOutput(health)) = commands_run(config, types.Health)
  assert health.status == "ok"
  assert health.version == Some("1.2.3")
  assert captured(collector) == ["GET", "/health", ""]
}

// ─── task ───────────────────────────────────────────────────────────────────

pub fn task_add_posts_create_body_test() {
  let #(_listener, port, collector) = stub_start_capture(201, task_json)
  let config = loopback(port)
  let args =
    types.TaskAddArgs(
      title: "T",
      description: None,
      level: None,
      priority: None,
      tags: [],
      parent_id: None,
    )
  let assert Ok(types.TaskCreated(task)) =
    commands_run(config, types.TaskAdd(args))
  assert task.id == "task-1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/tasks",
      "{\"title\":\"T\",\"description\":null,\"level\":\"ticket\",\"priority\":\"medium\",\"tags\":[],\"parent_id\":null}",
    ]
}

pub fn task_list_hits_tasks_endpoint_with_query_test() {
  let #(_listener, port, collector) = stub_start_capture(200, "[]")
  let config = loopback(port)
  let args =
    types.TaskListArgs(
      level: Some(models.Epic),
      status: None,
      parent_id: None,
      limit: Some(5),
      offset: None,
      ready: False,
    )
  let assert Ok(types.TaskListOutput(tasks)) =
    commands_run(config, types.TaskList(args))
  assert tasks == []
  assert captured(collector) == ["GET", "/api/v1/tasks?limit=5&level=epic", ""]
}

pub fn task_list_ready_hits_ready_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(200, task_json_array())
  let config = loopback(port)
  let args =
    types.TaskListArgs(
      level: None,
      status: None,
      parent_id: None,
      limit: None,
      offset: None,
      ready: True,
    )
  let assert Ok(types.TaskListOutput(tasks)) =
    commands_run(config, types.TaskList(args))
  assert tasks == [decoded_task()]
  assert captured(collector) == ["GET", "/api/v1/tasks/ready", ""]
}

pub fn task_show_hits_task_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(200, task_json)
  let config = loopback(port)
  let assert Ok(types.TaskShown(task)) =
    commands_run(config, types.TaskShow("task-1"))
  assert task.id == "task-1"
  assert captured(collector) == ["GET", "/api/v1/tasks/task-1", ""]
}

pub fn task_update_patches_only_given_fields_test() {
  let #(_listener, port, collector) = stub_start_capture(200, task_json)
  let config = loopback(port)
  let args =
    types.TaskUpdateArgs(
      title: None,
      description: None,
      level: None,
      priority: None,
      status: Some(models.Done),
      parent_id: None,
    )
  let assert Ok(types.TaskUpdated(_)) =
    commands_run(config, types.TaskUpdate("task-1", args))
  assert captured(collector)
    == [
      "PATCH",
      "/api/v1/tasks/task-1",
      "{\"status\":\"done\"}",
    ]
}

pub fn task_delete_cascade_sets_query_test() {
  let #(_listener, port, collector) = stub_start_capture(200, "")
  let config = loopback(port)
  let assert Ok(types.TaskDeleted(id, cascade)) =
    commands_run(config, types.TaskDelete("task-1", True))
  assert id == "task-1"
  assert cascade
  assert captured(collector)
    == ["DELETE", "/api/v1/tasks/task-1?cascade=true", ""]
}

pub fn task_delete_without_cascade_test() {
  let #(_listener, port, collector) = stub_start_capture(200, "")
  let config = loopback(port)
  let assert Ok(types.TaskDeleted(_, cascade)) =
    commands_run(config, types.TaskDelete("task-1", False))
  assert cascade == False
  assert captured(collector)
    == ["DELETE", "/api/v1/tasks/task-1?cascade=false", ""]
}

pub fn task_depend_posts_dependencies_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(201, "{\"message\":\"Dependency added\"}")
  let config = loopback(port)
  let assert Ok(types.DependencyAdded(task_id, depends_on)) =
    commands_run(config, types.TaskDepend("task-2", "task-1"))
  assert task_id == "task-2"
  assert depends_on == "task-1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/tasks/task-2/dependencies",
      "{\"depends_on\":\"task-1\"}",
    ]
}

pub fn task_undepend_deletes_dependencies_edge_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "{\"message\":\"Dependency removed\"}")
  let config = loopback(port)
  let assert Ok(types.DependencyRemoved(task_id, depends_on)) =
    commands_run(config, types.TaskUndepend("task-2", "task-1"))
  assert task_id == "task-2"
  assert depends_on == "task-1"
  assert captured(collector)
    == [
      "DELETE",
      "/api/v1/tasks/task-2/dependencies/task-1",
      "",
    ]
}

pub fn task_blockers_hits_blockers_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, task_blocker_array())
  let config = loopback(port)
  let assert Ok(types.BlockersShown(task_id, blockers)) =
    commands_run(config, types.TaskBlockers("task-3"))
  assert task_id == "task-3"
  assert blockers == [decoded_blocked_task()]
  assert captured(collector) == ["GET", "/api/v1/tasks/task-3/blockers", ""]
}

// ─── task sections ──────────────────────────────────────────────────────────

pub fn task_sections_hits_sections_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "[" <> section_json <> "]")
  let config = loopback(port)
  let assert Ok(types.SectionsShown(task_id, sections)) =
    commands_run(config, types.TaskSections("task-1"))
  assert task_id == "task-1"
  let assert [section] = sections
  assert section.id == "sec-1"
  assert section.section_type == models.Goal
  assert section.content == "Ship the release"
  assert captured(collector) == ["GET", "/api/v1/tasks/task-1/sections", ""]
}

pub fn task_section_add_posts_section_body_test() {
  let #(_listener, port, collector) = stub_start_capture(201, section_json)
  let config = loopback(port)
  let assert Ok(types.SectionCreated(section)) =
    commands_run(
      config,
      types.TaskSectionAdd(
        "task-1",
        types.TaskSectionAddArgs(
          section_type: models.Goal,
          content: "Ship the release",
        ),
      ),
    )
  assert section.id == "sec-1"
  assert section.task_id == "task-1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/tasks/task-1/sections",
      "{\"section_type\":\"goal\",\"content\":\"Ship the release\"}",
    ]
}

pub fn task_sections_engine_without_api_is_readable_error_test() {
  // Crystalline builds predating crystalline#16 answer 404 on the sections
  // route; the CLI must report it as a request error, not crash or lie.
  let #(_listener, port, _collector) =
    stub_start_capture(404, "{\"error\":\"not_found\"}")
  let config = loopback(port)
  let assert Error(types.RequestError(config.HttpError(
    404,
    "{\"error\":\"not_found\"}",
  ))) = commands_run(config, types.TaskSections("task-1"))
}

// ─── flow ───────────────────────────────────────────────────────────────────

pub fn flow_templates_hits_templates_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "[" <> template_json <> "]")
  let config = loopback(port)
  let assert Ok(types.TemplatesListed(templates)) =
    commands_run(config, types.FlowTemplates)
  assert templates == [decoded_template()]
  assert captured(collector) == ["GET", "/api/v1/flow-templates", ""]
}

pub fn flow_template_show_hits_one_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(200, template_json)
  let config = loopback(port)
  let assert Ok(types.TemplateShown(template)) =
    commands_run(config, types.FlowTemplateShow("linear"))
  assert template.id == "linear"
  assert captured(collector) == ["GET", "/api/v1/flow-templates/linear", ""]
}

pub fn flow_start_posts_flow_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(201, instance_json)
  let config = loopback(port)
  let assert Ok(types.FlowStarted(instance, task_id)) =
    commands_run(config, types.FlowStart("task-1", "linear"))
  assert instance.id == "flow-1"
  assert task_id == "task-1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/tasks/task-1/flow",
      "{\"template_id\":\"linear\"}",
    ]
}

pub fn flow_status_hits_flow_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(200, state_json)
  let config = loopback(port)
  let assert Ok(types.FlowStatusShown(state)) =
    commands_run(config, types.FlowStatus("flow-1"))
  assert state.id == "state-1"
  assert state.status == models.ExecRunning
  assert captured(collector) == ["GET", "/api/v1/flows/flow-1", ""]
}

pub fn flow_advance_hits_advance_endpoint_and_decodes_action_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, run_step_action_json)
  let config = loopback(port)
  let assert Ok(types.FlowAdvanced(instance_id, action)) =
    commands_run(config, types.FlowAdvance("flow-1"))
  assert instance_id == "flow-1"
  let assert models.RunStep(node, prompt) = action
  assert node.id == "n1"
  assert node.name == "Research"
  assert prompt == "do it"
  assert captured(collector) == ["POST", "/api/v1/flows/flow-1/advance", ""]
}

pub fn flow_complete_step_posts_output_test() {
  let #(_listener, port, collector) = stub_start_capture(200, state_json)
  let config = loopback(port)
  let assert Ok(types.StepCompleted(step_id, _)) =
    commands_run(config, types.FlowCompleteStep("flow-1", "n1", "done"))
  assert step_id == "n1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/steps/n1/complete",
      "{\"output\":\"done\"}",
    ]
}

pub fn flow_input_posts_input_test() {
  let #(_listener, port, collector) = stub_start_capture(200, state_json)
  let config = loopback(port)
  let assert Ok(types.InputProvided(instance_id, _)) =
    commands_run(config, types.FlowInput("flow-1", "approved"))
  assert instance_id == "flow-1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/input",
      "{\"input\":\"approved\"}",
    ]
}

pub fn flow_reject_posts_reason_test() {
  let #(_listener, port, collector) = stub_start_capture(200, state_json)
  let config = loopback(port)
  let assert Ok(types.FlowRejected(instance_id, _)) =
    commands_run(config, types.FlowReject("flow-1", Some("out of scope")))
  assert instance_id == "flow-1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/reject",
      "{\"reason\":\"out of scope\"}",
    ]
}

pub fn flow_reject_defaults_reason_test() {
  let #(_listener, port, collector) = stub_start_capture(200, state_json)
  let config = loopback(port)
  let assert Ok(_) = commands_run(config, types.FlowReject("flow-1", None))
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/reject",
      "{\"reason\":\"Rejected via the facet CLI\"}",
    ]
}

// ─── exec ───────────────────────────────────────────────────────────────────

pub fn exec_history_hits_executions_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "[" <> step_json <> "]")
  let config = loopback(port)
  let assert Ok(types.ExecHistoryShown(task_id, steps)) =
    commands_run(config, types.ExecHistory("task-1"))
  assert task_id == "task-1"
  assert steps == [decoded_step()]
  assert captured(collector) == ["GET", "/api/v1/tasks/task-1/executions", ""]
}

pub fn exec_show_hits_execution_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(200, step_json)
  let config = loopback(port)
  let assert Ok(types.ExecShown(step)) =
    commands_run(config, types.ExecShow("step-1"))
  assert step.id == "step-1"
  assert captured(collector) == ["GET", "/api/v1/executions/step-1", ""]
}

pub fn exec_active_hits_active_endpoint_test() {
  let #(_listener, port, collector) = stub_start_capture(200, "[]")
  let config = loopback(port)
  let assert Ok(types.ExecActiveShown(steps)) =
    commands_run(config, types.ExecActive)
  assert steps == []
  assert captured(collector) == ["GET", "/api/v1/executions/active", ""]
}

pub fn exec_logs_defaults_to_limit_100_test() {
  let #(_listener, port, collector) = stub_start_capture(200, "[]")
  let config = loopback(port)
  let assert Ok(types.LogsShown(logs, _)) =
    commands_run(
      config,
      types.ExecLogs("step-1", types.ExecLogsArgs(limit: None, before: None)),
    )
  assert logs == []
  assert captured(collector)
    == ["GET", "/api/v1/executions/step-1/logs?limit=100", ""]
}

pub fn exec_logs_passes_paging_params_and_derives_has_more_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "[" <> log_json <> "," <> log_json <> "]")
  let config = loopback(port)
  let assert Ok(types.LogsShown(logs, paging)) =
    commands_run(
      config,
      types.ExecLogs(
        "step-1",
        types.ExecLogsArgs(limit: Some(2), before: Some(5)),
      ),
    )
  assert list_length(logs) == 2
  assert paging.has_more
  assert paging.continue_before == Some(1)
  assert captured(collector)
    == [
      "GET",
      "/api/v1/executions/step-1/logs?limit=2&before_sequence=5",
      "",
    ]
}

pub fn exec_logs_page_not_full_has_no_more_test() {
  let #(_listener, port, _collector) =
    stub_start_capture(200, "[" <> log_json <> "]")
  let config = loopback(port)
  let assert Ok(types.LogsShown(logs, paging)) =
    commands_run(
      config,
      types.ExecLogs(
        "step-1",
        types.ExecLogsArgs(limit: Some(100), before: None),
      ),
    )
  assert list_length(logs) == 1
  assert paging.has_more == False
  assert paging.continue_before == Some(1)
}

// ─── errors and exit codes ──────────────────────────────────────────────────

pub fn http_error_becomes_readable_request_error_test() {
  let #(_listener, port, _collector) =
    stub_start_capture(404, "{\"error\":\"nope\"}")
  let config = loopback(port)
  let assert Error(types.RequestError(config.HttpError(
    404,
    "{\"error\":\"nope\"}",
  ))) = commands_run(config, types.TaskShow("missing"))
}

pub fn network_failure_becomes_request_error_test() {
  let config = config.Config(base_url: "http://127.0.0.1:1", token: None)
  let assert Error(types.RequestError(config.NetworkError(_))) =
    commands_run(config, types.Health)
}

pub fn app_main_exit_codes_test() {
  // Success against a live stub (one-shot, so a fresh stub per call).
  let #(_l1, p1, _c1) = stub_start_capture(200, "{\"status\":\"ok\"}")
  assert app.main(["--url", "http://127.0.0.1:" <> int.to_string(p1), "health"])
    == 0

  let #(_l2, p2, _c2) = stub_start_capture(200, "{\"status\":\"ok\"}")
  assert app.main([
      "--url",
      "http://127.0.0.1:" <> int.to_string(p2),
      "--json",
      "health",
    ])
    == 0

  // A 404 from the server is a readable error and exit 1.
  let #(_l3, p3, _c3) = stub_start_capture(404, "{\"error\":\"nope\"}")
  assert app.main([
      "--url",
      "http://127.0.0.1:" <> int.to_string(p3),
      "task",
      "show",
      "missing",
    ])
    == 1

  // Usage errors are exit 1; help is exit 0.
  assert app.main([]) == 1
  assert app.main(["bogus"]) == 1
  assert app.main(["--help"]) == 0
  assert app.main(["help"]) == 0
}

// ─── helpers ────────────────────────────────────────────────────────────────

fn commands_run(
  config: config.Config,
  command: types.Command,
) -> Result(types.Output, types.CliError) {
  commands.run(config, command)
}

fn loopback(port: Int) -> config.Config {
  config.Config(
    base_url: "http://127.0.0.1:" <> int.to_string(port),
    token: None,
  )
}

fn captured(collector: dynamic.Dynamic) -> List(String) {
  case decode.run(stub_get_captured(collector), decode.list(decode.string)) {
    Ok(values) -> values
    Error(_) -> []
  }
}

fn task_json_array() -> String {
  "[" <> task_json <> "]"
}

fn task_blocker_array() -> String {
  "[" <> blocked_task_json <> "]"
}

fn decoded_task() -> models.Task {
  let assert Ok(task) = models.decode_json(task_json, models.decode_task())
  task
}

fn decoded_blocked_task() -> models.Task {
  let assert Ok(task) =
    models.decode_json(blocked_task_json, models.decode_task())
  task
}

fn decoded_template() -> models.FlowTemplate {
  let assert Ok(template) =
    models.decode_json(template_json, models.decode_flow_template())
  template
}

fn decoded_step() -> models.StepExecution {
  let assert Ok(step) =
    models.decode_json(step_json, models.decode_step_execution())
  step
}

fn list_length(list: List(a)) -> Int {
  case list {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}
