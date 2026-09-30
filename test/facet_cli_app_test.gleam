//// End-to-end CLI tests: every command is dispatched against a one-shot stub
//// server, and the captured request asserts the exact method, path and body
//// the client sends. This is the "every command correct vs running
//// instance" acceptance criterion, pinned down in code.

import facet/cli/app
import facet/cli/commands
import facet/cli/render
import facet/cli/types
import facet/config
import facet/ffi
import facet/models
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

@external(erlang, "facet_stderr", "capture")
fn capture_stderr(run: fn() -> a) -> #(a, String)

@external(erlang, "facet_stub_server", "start_capture")
fn stub_start_capture(
  status: Int,
  body: String,
) -> #(dynamic.Dynamic, Int, dynamic.Dynamic)

@external(erlang, "facet_stub_server", "start_capture_script")
fn stub_start_script(
  responses: List(#(Int, String)),
) -> #(dynamic.Dynamic, Int, dynamic.Dynamic)

@external(erlang, "facet_stub_server", "get_captured")
fn stub_get_captured(collector: dynamic.Dynamic) -> dynamic.Dynamic

@external(erlang, "facet_stub_server", "get_captured_all")
fn stub_get_all(collector: dynamic.Dynamic) -> dynamic.Dynamic

@external(erlang, "facet_stub_server", "get_captured_headers")
fn stub_get_headers(collector: dynamic.Dynamic) -> dynamic.Dynamic

// ─── Wire-format fixtures ───────────────────────────────────────────────────
//
// Flow fixtures mirror Crystalline's `http/routes/flows.gleam` verbatim: the
// template/instance node graphs travel as arrays, `POST /tasks/:id/flow`
// answers `{"instance","execution"}`, and every step route answers
// `{"execution","action"}` with the action tagged `"type"`.

const task_json = "{\"id\":\"task-1\",\"short_id\":\"00000001\",\"title\":\"T\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"medium\",\"status\":\"todo\",\"tags\":[],\"parent_id\":null,\"archived\":false,\"created_at\":1,\"updated_at\":2}"

const blocked_task_json = "{\"id\":\"task-2\",\"short_id\":\"00000002\",\"title\":\"Dependent\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"low\",\"status\":\"blocked\",\"tags\":[],\"parent_id\":null,\"archived\":false,\"created_at\":1,\"updated_at\":2}"

const node_json = "{\"id\":\"n1\",\"name\":\"Research\",\"node_type\":\"step\",\"goal\":\"Understand the problem\",\"prompt\":\"do it\"}"

const input_node_json = "{\"id\":\"n3\",\"name\":\"Confirm\",\"node_type\":\"human_input\",\"goal\":\"Get confirmation\"}"

/// `GET /flow-templates` — summaries: no graph, just counts.
const template_summary_json = "{\"id\":\"linear\",\"slug\":\"linear\",\"name\":\"Linear\",\"description\":\"\",\"initial_node_id\":\"n1\",\"node_count\":1,\"transition_count\":0}"

/// `GET /flow-templates/:id` — the full template, nodes as an array.
const template_json = "{\"id\":\"linear\",\"slug\":\"linear\",\"name\":\"Linear\",\"description\":\"\",\"initial_node_id\":\"n1\",\"nodes\":["
  <> node_json
  <> "],\"transitions\":[],\"on_done_template_id\":null,\"on_reject_template_id\":null}"

const instance_json = "{\"id\":\"flow-1\",\"template_id\":\"linear\",\"task_id\":\"task-1\",\"initial_node_id\":\"n1\",\"nodes\":["
  <> node_json
  <> "],\"transitions\":[],\"on_done_template_id\":null,\"on_reject_template_id\":null}"

const pending_execution_json = "{\"id\":\"exec-1\",\"instance_id\":\"flow-1\",\"task_id\":\"task-1\",\"status\":\"pending\",\"current_node_id\":null,\"started_at\":null,\"completed_at\":null}"

const running_execution_json = "{\"id\":\"exec-1\",\"instance_id\":\"flow-1\",\"task_id\":\"task-1\",\"status\":\"running\",\"current_node_id\":\"n1\",\"started_at\":5,\"completed_at\":null}"

const awaiting_execution_json = "{\"id\":\"exec-1\",\"instance_id\":\"flow-1\",\"task_id\":\"task-1\",\"status\":\"awaiting_input\",\"current_node_id\":\"n3\",\"started_at\":5,\"completed_at\":null}"

const completed_execution_json = "{\"id\":\"exec-1\",\"instance_id\":\"flow-1\",\"task_id\":\"task-1\",\"status\":\"completed\",\"current_node_id\":\"n2\",\"started_at\":5,\"completed_at\":30}"

const run_step_action_json = "{\"type\":\"run_step\",\"node\":"
  <> node_json
  <> ",\"prompt\":\"do it\"}"

const await_input_action_json = "{\"type\":\"await_input\",\"node\":"
  <> input_node_json
  <> "}"

const complete_action_json = "{\"type\":\"flow_complete\"}"

const reject_action_json = "{\"type\":\"flow_reject\"}"

const state_json = "{\"id\":\"state-1\",\"status\":\"running\",\"task_id\":\"task-1\"}"

const step_json = "{\"id\":\"step-1\",\"status\":\"completed\",\"node_id\":\"n1\",\"task_id\":\"task-1\"}"

const log_json = "{\"id\":\"log-1\",\"event_type\":\"text\",\"payload\":\"{}\",\"sequence\":1}"

const section_json = "{\"id\":\"sec-1\",\"task_id\":\"task-1\",\"section_type\":\"goal\",\"content\":\"Ship the release\",\"code_ref\":null,\"order\":1}"

const project_json = "{\"id\":\"proj-1\",\"slug\":\"acme\",\"name\":\"Acme\",\"description\":\"\",\"created_at\":1,\"updated_at\":2}"

const artifact_json = "{\"id\":\"art-1\",\"task_id\":\"task-1\",\"logical_name\":\"plan.json\",\"content\":{\"ok\":true},\"created_at\":1,\"updated_at\":2}"

const cancelled_state_json = "{\"id\":\"state-1\",\"instance_id\":\"flow-1\",\"task_id\":\"task-1\",\"status\":\"cancelled\",\"current_node_id\":null,\"started_at\":5,\"completed_at\":99}"

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
    stub_start_capture(200, "[" <> template_summary_json <> "]")
  let config = loopback(port)
  let assert Ok(types.TemplatesListed(templates)) =
    commands_run(config, types.FlowTemplates)
  assert templates == [decoded_summary_template()]
  assert captured(collector) == ["GET", "/api/v1/flow-templates", ""]
}

pub fn flow_template_show_decodes_the_engine_node_array_test() {
  // The engine serialises the graph as an array of nodes; the CLI keeps it
  // keyed by node id.
  let #(_listener, port, collector) = stub_start_capture(200, template_json)
  let config = loopback(port)
  let assert Ok(types.TemplateShown(template)) =
    commands_run(config, types.FlowTemplateShow("linear"))
  assert template.id == "linear"
  assert template.initial_node_id == "n1"
  let assert Ok(node) = dict.get(template.nodes, "n1")
  assert node.name == "Research"
  assert node.goal == "Understand the problem"
  assert captured(collector) == ["GET", "/api/v1/flow-templates/linear", ""]
}

pub fn flow_start_decodes_the_instance_execution_envelope_test() {
  let #(_listener, port, collector) =
    stub_start_capture(
      201,
      "{\"instance\":"
        <> instance_json
        <> ",\"execution\":"
        <> pending_execution_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.FlowStarted(started)) =
    commands_run(config, types.FlowStart("task-1", "linear"))
  assert started.instance.id == "flow-1"
  assert started.instance.template_id == "linear"
  assert started.instance.task_id == "task-1"
  assert started.execution.status == models.ExecPending
  assert started.execution.instance_id == "flow-1"
  // The human render names the instance and its status.
  let rendered = render.render(types.FlowStarted(started))
  assert string.contains(rendered, "flow-1")
  assert string.contains(rendered, "pending")
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

pub fn flow_advance_decodes_the_execution_step_envelope_test() {
  let #(_listener, port, collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> running_execution_json
        <> ",\"action\":"
        <> run_step_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.FlowAdvanced(step)) =
    commands_run(config, types.FlowAdvance("flow-1"))
  assert step.execution.status == models.ExecRunning
  assert step.execution.instance_id == "flow-1"
  let assert models.RunStep(node, prompt) = step.action
  assert node.id == "n1"
  assert node.name == "Research"
  assert prompt == "do it"
  // The action type and its node reach the human render.
  let rendered = render.render(types.FlowAdvanced(step))
  assert string.contains(rendered, "run_step")
  assert string.contains(rendered, "n1 (Research)")
  assert string.contains(
    rendered,
    "facet flow complete-step flow-1 n1 --output",
  )
  assert captured(collector) == ["POST", "/api/v1/flows/flow-1/advance", ""]
}

pub fn flow_advance_flow_complete_is_terminal_test() {
  let #(_listener, port, _collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> completed_execution_json
        <> ",\"action\":"
        <> complete_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.FlowAdvanced(step)) =
    commands_run(config, types.FlowAdvance("flow-1"))
  assert step.execution.status == models.ExecCompleted
  assert step.action == models.FlowComplete
  let rendered = render.render(types.FlowAdvanced(step))
  assert string.contains(rendered, "flow_complete")
  assert string.contains(rendered, "the flow finished")
}

pub fn flow_advance_await_input_carries_the_human_node_test() {
  let #(_listener, port, _collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> awaiting_execution_json
        <> ",\"action\":"
        <> await_input_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.FlowAdvanced(step)) =
    commands_run(config, types.FlowAdvance("flow-1"))
  assert step.execution.status == models.ExecAwaitingInput
  let assert models.AwaitInput(node) = step.action
  assert node.id == "n3"
  assert node.node_type == models.HumanInput
  let rendered = render.render(types.FlowAdvanced(step))
  assert string.contains(rendered, "await_input")
  assert string.contains(rendered, "facet flow input flow-1 \"<text>\"")
}

pub fn flow_complete_step_posts_output_to_the_instance_route_test() {
  // The engine identifies the step from the execution's current node, so the
  // path carries the instance only.
  let #(_listener, port, collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> completed_execution_json
        <> ",\"action\":"
        <> complete_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.StepCompleted(step_id, step)) =
    commands_run(config, types.FlowCompleteStep("flow-1", "n1", "done"))
  assert step_id == "n1"
  assert step.action == models.FlowComplete
  assert step.execution.status == models.ExecCompleted
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/complete",
      "{\"output\":\"done\"}",
    ]
}

pub fn flow_input_posts_input_and_decodes_the_next_action_test() {
  let #(_listener, port, collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> running_execution_json
        <> ",\"action\":"
        <> run_step_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.InputProvided(step)) =
    commands_run(config, types.FlowInput("flow-1", "approved"))
  let assert models.RunStep(node, _) = step.action
  assert node.id == "n1"
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/input",
      "{\"input\":\"approved\"}",
    ]
}

pub fn flow_reject_posts_reason_test() {
  let #(_listener, port, collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> completed_execution_json
        <> ",\"action\":"
        <> reject_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(types.FlowRejected(step)) =
    commands_run(config, types.FlowReject("flow-1", Some("out of scope")))
  assert step.action == models.FlowReject
  assert step.execution.instance_id == "flow-1"
  let rendered = render.render(types.FlowRejected(step))
  assert string.contains(rendered, "flow rejected: flow-1")
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/reject",
      "{\"reason\":\"out of scope\"}",
    ]
}

pub fn flow_reject_defaults_reason_test() {
  let #(_listener, port, collector) =
    stub_start_capture(
      200,
      "{\"execution\":"
        <> completed_execution_json
        <> ",\"action\":"
        <> reject_action_json
        <> "}",
    )
  let config = loopback(port)
  let assert Ok(_) = commands_run(config, types.FlowReject("flow-1", None))
  assert captured(collector)
    == [
      "POST",
      "/api/v1/flows/flow-1/reject",
      "{\"reason\":\"Rejected via the facet CLI\"}",
    ]
}

pub fn flow_advance_on_an_unknown_instance_reports_the_engine_error_test() {
  // A 404 with the engine's JSON error body: exit 1, and the engine's message
  // on stderr (nothing on stdout).
  let #(_listener, port, _collector) =
    stub_start_capture(404, "{\"error\":\"Flow instance not found: flow-9\"}")
  let url = "http://127.0.0.1:" <> int.to_string(port)
  let #(exit_code, stderr) =
    capture_stderr(fn() {
      app.main(["--url", url, "flow", "advance", "flow-9"])
    })
  assert exit_code == 1
  assert string.contains(stderr, "Flow instance not found: flow-9")
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
  let config =
    config.Config(base_url: "http://127.0.0.1:1", token: None, project: None)
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

// ─── init / project scope ───────────────────────────────────────────────────

pub fn init_creates_project_and_persists_scope_test() {
  let config_path = tmp_config_path("init-new")
  set_env("FACET_CONFIG", config_path)
  let #(_listener, port, collector) =
    stub_start_script([
      #(404, "{\"error\":\"Project not found\"}"),
      #(201, project_json),
    ])
  let assert Ok(types.ProjectInitialized(project, path)) =
    commands_run(
      loopback(port),
      types.Init(types.InitArgs(slug: "acme", name: Some("Acme"))),
    )
  assert project.id == "proj-1"
  assert project.slug == "acme"
  assert path == config_path
  assert captured_all(collector)
    == [
      ["GET", "/api/v1/projects/acme", ""],
      ["POST", "/api/v1/projects", "{\"slug\":\"acme\",\"name\":\"Acme\"}"],
    ]
  // The scope is persisted to the config file: reading it back (still
  // pointed at that file) resolves the project without any env override.
  assert config.read_config_file().project == Some("acme")
  unset_env("FACET_CONFIG")
}

pub fn init_reuses_an_existing_project_without_creating_test() {
  let config_path = tmp_config_path("init-existing")
  set_env("FACET_CONFIG", config_path)
  let #(_listener, port, collector) = stub_start_capture(200, project_json)
  let assert Ok(types.ProjectInitialized(project, _)) =
    commands_run(
      loopback(port),
      types.Init(types.InitArgs(slug: "acme", name: None)),
    )
  assert project.slug == "acme"
  assert captured_all(collector) == [["GET", "/api/v1/projects/acme", ""]]
  unset_env("FACET_CONFIG")
}

pub fn init_defaults_the_name_to_the_slug_test() {
  let config_path = tmp_config_path("init-name")
  set_env("FACET_CONFIG", config_path)
  let #(_listener, port, collector) =
    stub_start_script([
      #(404, "{\"error\":\"Project not found\"}"),
      #(201, project_json),
    ])
  let assert Ok(_) =
    commands_run(
      loopback(port),
      types.Init(types.InitArgs(slug: "acme", name: None)),
    )
  assert captured_all(collector)
    == [
      ["GET", "/api/v1/projects/acme", ""],
      ["POST", "/api/v1/projects", "{\"slug\":\"acme\",\"name\":\"acme\"}"],
    ]
  unset_env("FACET_CONFIG")
}

pub fn init_recovers_when_the_create_loses_a_race_test() {
  let config_path = tmp_config_path("init-race")
  set_env("FACET_CONFIG", config_path)
  let #(_listener, port, collector) =
    stub_start_script([
      #(404, "{\"error\":\"Project not found\"}"),
      #(409, "{\"error\":\"Project slug already exists: acme\"}"),
      #(200, project_json),
    ])
  let assert Ok(types.ProjectInitialized(project, _)) =
    commands_run(
      loopback(port),
      types.Init(types.InitArgs(slug: "acme", name: None)),
    )
  assert project.slug == "acme"
  assert list.length(captured_all(collector)) == 3
  unset_env("FACET_CONFIG")
}

pub fn scoped_commands_send_the_project_header_test() {
  let #(_listener, port, collector) = stub_start_capture(200, task_path_json())
  let assert Ok(types.TaskPathShown(task_id, path)) =
    commands_run(scoped(port, "acme"), types.Path("task-3"))
  assert task_id == "task-3"
  assert list.length(path) == 3
  assert captured(collector) == ["GET", "/api/v1/tasks/task-3/path", ""]
  assert list.contains(
    captured_headers(collector),
    "x-crystalline-project: acme",
  )
}

pub fn unscoped_commands_omit_the_project_header_test() {
  let #(_listener, port, collector) = stub_start_capture(200, task_path_json())
  let assert Ok(_) = commands_run(loopback(port), types.Path("task-3"))
  assert list.contains(
      captured_headers(collector),
      "x-crystalline-project: acme",
    )
    == False
}

pub fn unknown_project_404_message_points_at_init_test() {
  let client_config = scoped(1, "ghost")
  assert app.error_message(
      client_config,
      types.RequestError(config.HttpError(
        404,
        "{\"error\":\"Unknown project: ghost\"}",
      )),
    )
    == "unknown project: run `facet init <slug>` to create it, or pass --project <id|slug>"

  // An unrelated 404 keeps the engine's message verbatim.
  assert app.error_message(
      client_config,
      types.RequestError(config.HttpError(404, "{\"error\":\"Task not found\"}")),
    )
    == "HTTP 404: {\"error\":\"Task not found\"}"
}

// ─── path / stop ────────────────────────────────────────────────────────────

pub fn path_hits_the_path_endpoint_and_decodes_root_to_task_test() {
  let #(_listener, port, collector) = stub_start_capture(200, task_path_json())
  let assert Ok(types.TaskPathShown(task_id, path)) =
    commands_run(loopback(port), types.Path("task-3"))
  assert task_id == "task-3"
  assert list.map(path, fn(task) { task.id }) == ["task-1", "task-2", "task-3"]
  assert captured(collector) == ["GET", "/api/v1/tasks/task-3/path", ""]
}

pub fn stop_posts_cancel_and_decodes_the_cancelled_execution_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, cancelled_state_json)
  let assert Ok(types.FlowCancelled(instance_id, state)) =
    commands_run(loopback(port), types.Stop("flow-1"))
  assert instance_id == "flow-1"
  assert state.status == models.ExecCancelled
  assert state.completed_at == Some(99)
  assert captured(collector) == ["POST", "/api/v1/flows/flow-1/cancel", ""]
}

pub fn stop_on_a_non_running_execution_surfaces_the_409_message_test() {
  let #(_listener, port, _collector) =
    stub_start_capture(
      409,
      "{\"error\":\"Cannot cancel: execution is pending\"}",
    )
  let assert Error(types.RequestError(config.HttpError(409, body))) =
    commands_run(loopback(port), types.Stop("flow-1"))
  assert string.contains(body, "Cannot cancel: execution is pending")
}

pub fn stop_after_cancel_surfaces_the_was_cancelled_409_test() {
  // The engine refuses a later advance with 409 "…was cancelled"; the CLI
  // must report it verbatim rather than swallowing it.
  let #(_listener, port, _collector) =
    stub_start_capture(
      409,
      "{\"error\":\"Cannot advance: execution was cancelled\"}",
    )
  let assert Error(types.RequestError(config.HttpError(409, body))) =
    commands_run(loopback(port), types.FlowAdvance("flow-1"))
  assert string.contains(body, "was cancelled")
}

// ─── task ref / unref ───────────────────────────────────────────────────────

pub fn task_ref_creates_a_section_with_code_ref_test() {
  let section_json =
    "{\"id\":\"sec-9\",\"task_id\":\"task-1\",\"section_type\":\"context\",\"content\":\"src/main.gleam\",\"code_ref\":{\"path\":\"src/main.gleam\",\"line_start\":10,\"line_end\":20,\"name\":\"main\",\"description\":null},\"order\":1}"
  let #(_listener, port, collector) = stub_start_capture(201, section_json)
  let assert Ok(types.CodeRefAdded(section)) =
    commands_run(
      loopback(port),
      types.TaskRef(
        "task-1",
        types.TaskRefArgs(
          code_path: "src/main.gleam",
          line_start: Some(10),
          line_end: Some(20),
          name: Some("main"),
          description: None,
          section_type: models.Context,
          content: "src/main.gleam",
        ),
      ),
    )
  assert section.id == "sec-9"
  let assert Some(code_ref) = section.code_ref
  assert code_ref.path == "src/main.gleam"
  assert code_ref.line_start == Some(10)
  assert code_ref.line_end == Some(20)
  assert captured(collector)
    == [
      "POST",
      "/api/v1/tasks/task-1/sections",
      "{\"code_ref\":{\"path\":\"src/main.gleam\",\"line_start\":10,\"line_end\":20,\"name\":\"main\",\"description\":null},\"section_type\":\"context\",\"content\":\"src/main.gleam\"}",
    ]
}

pub fn task_unref_patches_the_section_to_clear_code_ref_test() {
  let #(_listener, port, collector) = stub_start_capture(200, section_json)
  let assert Ok(types.CodeRefCleared(section_id, section)) =
    commands_run(loopback(port), types.TaskUnref("task-1", "sec-1"))
  assert section_id == "sec-1"
  assert section.code_ref == None
  assert captured(collector)
    == ["PATCH", "/api/v1/sections/sec-1", "{\"code_ref\":null}"]
}

// ─── artifacts ──────────────────────────────────────────────────────────────

pub fn artifact_list_hits_the_task_artifacts_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "[" <> artifact_json <> "]")
  let assert Ok(types.ArtifactsListed(task_id, artifacts)) =
    commands_run(scoped(port, "acme"), types.ArtifactList("task-1"))
  assert task_id == "task-1"
  let assert [artifact] = artifacts
  assert artifact.logical_name == "plan.json"
  assert captured(collector) == ["GET", "/api/v1/tasks/task-1/artifacts", ""]
  assert list.contains(
    captured_headers(collector),
    "x-crystalline-project: acme",
  )
}

pub fn artifact_get_encodes_the_logical_name_test() {
  let #(_listener, port, collector) = stub_start_capture(200, artifact_json)
  let assert Ok(types.ArtifactShown(artifact)) =
    commands_run(loopback(port), types.ArtifactGet("task-1", "release notes"))
  assert artifact.logical_name == "plan.json"
  assert captured(collector)
    == [
      "GET",
      "/api/v1/tasks/task-1/artifacts/release%20notes",
      "",
    ]
}

pub fn artifact_put_posts_the_parsed_json_content_test() {
  let #(_listener, port, collector) = stub_start_capture(200, artifact_json)
  let assert Ok(types.ArtifactStored(_)) =
    commands_run(
      loopback(port),
      types.ArtifactPut("task-1", "plan.json", types.InlineContent("[1,2,3]")),
    )
  assert captured(collector)
    == [
      "PUT",
      "/api/v1/tasks/task-1/artifacts/plan.json",
      "{\"content\":[1,2,3]}",
    ]
}

pub fn artifact_put_round_trips_nested_object_content_test() {
  // The engine echoes the stored content; whatever we sent must come back
  // structurally intact.
  let content =
    "{\"id\":\"art-2\",\"task_id\":\"task-1\",\"logical_name\":\"x\",\"content\":{\"nested\":{\"n\":[1,2],\"ok\":true}},\"created_at\":1,\"updated_at\":2}"
  let #(_listener, port, collector) = stub_start_capture(200, content)
  let assert Ok(types.ArtifactStored(artifact)) =
    commands_run(
      loopback(port),
      types.ArtifactPut(
        "task-1",
        "x",
        types.InlineContent("{\"nested\":{\"n\":[1,2],\"ok\":true}}"),
      ),
    )
  let rendered = models.encode_json(artifact.content)
  assert string.contains(rendered, "\"nested\"")
  assert string.contains(rendered, "\"n\":[1,2]")
  assert string.contains(rendered, "\"ok\":true")
  // The wire body carries the same nested JSON.
  let body = case captured(collector) {
    [_, _, body] -> body
    _ -> ""
  }
  assert string.contains(body, "\"nested\"")
  assert string.contains(body, "\"n\":[1,2]")
}

pub fn artifact_put_rejects_invalid_json_test() {
  let #(_listener, port, _collector) = stub_start_capture(200, artifact_json)
  let assert Error(types.UsageError(message)) =
    commands_run(
      loopback(port),
      types.ArtifactPut("task-1", "x", types.InlineContent("not json")),
    )
  assert message == "artifact put --content is not valid JSON"
}

pub fn artifact_delete_hits_the_named_endpoint_test() {
  let #(_listener, port, collector) =
    stub_start_capture(200, "{\"message\":\"Artifact deleted\"}")
  let assert Ok(types.ArtifactDeleted(task_id, logical_name)) =
    commands_run(loopback(port), types.ArtifactDelete("task-1", "plan.json"))
  assert task_id == "task-1"
  assert logical_name == "plan.json"
  assert captured(collector)
    == ["DELETE", "/api/v1/tasks/task-1/artifacts/plan.json", ""]
}

pub fn artifact_put_dash_reads_stdin_test() {
  let #(_listener, port, collector) = stub_start_capture(200, artifact_json)
  let url = "http://127.0.0.1:" <> int.to_string(port)
  assert app.main_with(
      [
        "--url",
        url,
        "artifact",
        "task-1",
        "put",
        "plan.json",
        "--content",
        "-",
      ],
      fn() { "{\"from\":\"stdin\"}" },
    )
    == 0
  assert captured(collector)
    == [
      "PUT",
      "/api/v1/tasks/task-1/artifacts/plan.json",
      "{\"content\":{\"from\":\"stdin\"}}",
    ]
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
    project: None,
  )
}

/// Loopback config scoped to a project, which makes the client send
/// `X-Crystalline-Project`.
fn scoped(port: Int, project: String) -> config.Config {
  config.Config(
    base_url: "http://127.0.0.1:" <> int.to_string(port),
    token: None,
    project: Some(project),
  )
}

/// A unique config path so parallel or repeated runs never share state.
fn tmp_config_path(label: String) -> String {
  "/tmp/facet-test-"
  <> label
  <> "-"
  <> int.to_string(int.random(1_000_000_000))
  <> ".json"
}

fn set_env(name: String, value: String) -> Nil {
  let _ = ffi.putenv(name, value)
  Nil
}

fn unset_env(name: String) -> Nil {
  let _ = ffi.unsetenv(name)
  Nil
}

/// A three-element path: task-3 nested two levels below task-1.
fn task_path_json() -> String {
  "{\"path\":["
  <> task_at("task-1", "Root")
  <> ","
  <> task_at("task-2", "Middle")
  <> ","
  <> task_at("task-3", "Leaf")
  <> "]}"
}

fn task_at(id: String, title: String) -> String {
  "{\"id\":\""
  <> id
  <> "\",\"short_id\":\"s\",\"title\":\""
  <> title
  <> "\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"medium\",\"status\":\"todo\",\"tags\":[],\"parent_id\":null,\"archived\":false,\"created_at\":1,\"updated_at\":2}"
}

fn captured(collector: dynamic.Dynamic) -> List(String) {
  case decode.run(stub_get_captured(collector), decode.list(decode.string)) {
    Ok(values) -> values
    Error(_) -> []
  }
}

/// Every request a scripted stub served, in order, as [Method, Target, Body].
fn captured_all(collector: dynamic.Dynamic) -> List(List(String)) {
  case
    decode.run(stub_get_all(collector), decode.list(decode.list(decode.string)))
  {
    Ok(values) -> values
    Error(_) -> []
  }
}

/// Headers of the last captured request, lowercased as "name: value".
fn captured_headers(collector: dynamic.Dynamic) -> List(String) {
  case decode.run(stub_get_headers(collector), decode.list(decode.string)) {
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

fn decoded_summary_template() -> models.FlowTemplate {
  let assert Ok(template) =
    models.decode_json(template_summary_json, models.decode_flow_template())
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
