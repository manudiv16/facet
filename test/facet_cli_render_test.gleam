//// Tests for structured output rendering (human-readable + JSON).

import facet/cli/render
import facet/cli/types
import facet/models
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

fn sample_task() -> models.Task {
  models.Task(
    id: "task-9",
    short_id: "00000042",
    title: "Wire the client",
    description: "Talk to Crystalline over HTTP",
    level: models.Ticket,
    priority: models.High,
    status: models.InProgress,
    tags: ["facet", "http"],
    parent_id: Some("epic-1"),
    flow_template_id: Some("linear"),
    flow_instance_id: Some("flow-1"),
    current_node_id: Some("node-2"),
    worktree: None,
    archived: False,
    created_at: 1_700_000_000,
    updated_at: 1_700_000_100,
  )
}

pub fn health_renders_status_and_version_test() {
  let output =
    types.HealthOutput(models.HealthStatus(status: "ok", version: Some("2.0")))
  let rendered = render.render(output)
  assert string.contains(rendered, "status")
  assert string.contains(rendered, "ok")
  assert string.contains(rendered, "version")
  assert string.contains(rendered, "2.0")
}

pub fn health_renders_unknown_version_test() {
  let output =
    types.HealthOutput(models.HealthStatus(status: "ok", version: None))
  let rendered = render.render(output)
  assert string.contains(rendered, "version")
  assert string.contains(rendered, "(unknown)")
}

pub fn task_show_renders_fields_test() {
  let rendered = render.render(types.TaskShown(sample_task()))
  assert string.contains(rendered, "task-9")
  assert string.contains(rendered, "00000042")
  assert string.contains(rendered, "Wire the client")
  assert string.contains(rendered, "ticket")
  assert string.contains(rendered, "in_progress")
  assert string.contains(rendered, "flow-1")
  assert string.contains(rendered, "epic-1")
  assert string.contains(rendered, "facet, http")
}

pub fn empty_task_list_renders_no_tasks_test() {
  let rendered = render.render(types.TaskListOutput([]))
  assert rendered == "no tasks"
}

pub fn task_list_renders_header_and_rows_test() {
  let output = types.TaskListOutput([sample_task()])
  let rendered = render.render(output)
  assert string.contains(rendered, "ID")
  assert string.contains(rendered, "STATUS")
  assert string.contains(rendered, "Wire the client")
  assert string.contains(rendered, "task-9")
}

pub fn blockers_renders_header_line_test() {
  let output = types.BlockersShown("task-9", [sample_task()])
  let rendered = render.render(output)
  assert string.contains(rendered, "blockers of task-9:")
  assert string.contains(rendered, "Wire the client")
}

pub fn dependency_renders_arrow_test() {
  let added = render.render(types.DependencyAdded("task-2", "task-1"))
  assert added == "dependency added: task-2 -> task-1"
  let removed = render.render(types.DependencyRemoved("task-2", "task-1"))
  assert removed == "dependency removed: task-2 -x-> task-1"
}

pub fn flow_advance_run_step_shows_action_and_next_test() {
  let node =
    models.FlowNode(
      id: "node-2",
      name: "Implement",
      node_type: models.Step,
      goal: "Implement the feature",
      prompt: Some("Do it"),
      child_ids: [],
      branch_rules: [],
      loop_config: None,
      agent_config: None,
      output_schema: None,
    )
  let output = types.FlowAdvanced("flow-1", models.RunStep(node, "Do it now"))
  let rendered = render.render(output)
  assert string.contains(rendered, "run_step")
  assert string.contains(rendered, "node-2 (Implement)")
  assert string.contains(rendered, "Do it now")
  assert string.contains(rendered, "Implement the feature")
  assert string.contains(
    rendered,
    "facet flow complete-step flow-1 node-2 --output \"<result>\"",
  )
}

pub fn flow_advance_await_input_shows_hint_test() {
  let node =
    models.FlowNode(
      id: "node-3",
      name: "Confirm",
      node_type: models.HumanInput,
      goal: "Get user confirmation",
      prompt: None,
      child_ids: [],
      branch_rules: [],
      loop_config: None,
      agent_config: None,
      output_schema: None,
    )
  let output = types.FlowAdvanced("flow-1", models.AwaitInput(node))
  let rendered = render.render(output)
  assert string.contains(rendered, "await_input")
  assert string.contains(rendered, "facet flow input flow-1 \"<text>\"")
}

pub fn flow_advance_complete_renders_test() {
  let rendered =
    render.render(types.FlowAdvanced("flow-1", models.FlowComplete))
  assert string.contains(rendered, "flow_complete")
  assert string.contains(rendered, "facet task show <task-id>")
}

pub fn flow_advance_error_renders_message_test() {
  let output =
    types.FlowAdvanced("flow-1", models.ExecutionError("model blew up"))
  let rendered = render.render(output)
  assert string.contains(rendered, "execution_error")
  assert string.contains(rendered, "model blew up")
  assert string.contains(rendered, "facet flow reject flow-1 --reason")
}

pub fn empty_exec_history_renders_no_executions_test() {
  let rendered = render.render(types.ExecHistoryShown("task-1", []))
  assert string.contains(rendered, "no executions")
}

pub fn logs_render_paging_hint_test() {
  let log =
    models.SessionLog(
      id: "log-1",
      step_execution_id: "step-1",
      task_id: "task-1",
      event_type: "text",
      payload: "{\"content\":\"hi\"}",
      sequence: 7,
      created_at: 1_700_000_000,
    )
  let output =
    types.LogsShown(
      [log],
      types.LogPaging(has_more: True, continue_before: Some(7)),
    )
  let rendered = render.render(output)
  assert string.contains(rendered, "SEQ")
  assert string.contains(rendered, "{\"content\":\"hi\"}")
  assert string.contains(
    rendered,
    "more logs available; continue with: facet exec logs <id> --before 7",
  )
}

pub fn logs_without_more_omit_hint_test() {
  let log =
    models.SessionLog(
      id: "log-1",
      step_execution_id: "step-1",
      task_id: "task-1",
      event_type: "text",
      payload: "x",
      sequence: 1,
      created_at: 1,
    )
  let output =
    types.LogsShown(
      [log],
      types.LogPaging(has_more: False, continue_before: None),
    )
  let rendered = render.render(output)
  assert string.contains(rendered, "more logs available") == False
}

pub fn empty_logs_renders_no_logs_test() {
  let output =
    types.LogsShown([], types.LogPaging(has_more: False, continue_before: None))
  assert render.render(output) == "no logs"
}

// ─── JSON mode ──────────────────────────────────────────────────────────────

pub fn json_health_renders_object_test() {
  let output =
    types.HealthOutput(models.HealthStatus(status: "ok", version: Some("2.0")))
  let rendered = render.render_json(output)
  assert rendered == "{\"status\":\"ok\",\"version\":\"2.0\"}"
}

pub fn json_task_list_renders_array_test() {
  let output = types.TaskListOutput([sample_task()])
  let rendered = render.render_json(output)
  assert string.contains(rendered, "\"id\":\"task-9\"")
  assert string.contains(rendered, "\"title\":\"Wire the client\"")
}

pub fn json_flow_advance_renders_action_test() {
  let output = types.FlowAdvanced("flow-1", models.FlowComplete)
  let rendered = render.render_json(output)
  assert string.contains(rendered, "\"instance_id\":\"flow-1\"")
  assert string.contains(rendered, "\"kind\":\"flow_complete\"")
}

pub fn json_logs_include_paging_test() {
  let log =
    models.SessionLog(
      id: "l",
      step_execution_id: "s",
      task_id: "t",
      event_type: "text",
      payload: "p",
      sequence: 3,
      created_at: 1,
    )
  let output =
    types.LogsShown(
      [log],
      types.LogPaging(has_more: True, continue_before: Some(3)),
    )
  let rendered = render.render_json(output)
  assert string.contains(rendered, "\"has_more\":true")
  assert string.contains(rendered, "\"continue_before\":3")
}

pub fn empty_template_list_renders_no_templates_test() {
  let rendered = render.render(types.TemplatesListed([]))
  assert rendered == "no flow templates"
}

pub fn template_list_renders_rows_test() {
  let node =
    models.FlowNode(
      id: "n1",
      name: "Research",
      node_type: models.Step,
      goal: "Research it",
      prompt: None,
      child_ids: [],
      branch_rules: [],
      loop_config: None,
      agent_config: None,
      output_schema: None,
    )
  let template =
    models.FlowTemplate(
      id: "linear",
      name: "Linear",
      description: "one step",
      initial_node_id: "n1",
      nodes: dict.from_list([#("n1", node)]),
      transitions: [],
      on_done_template_id: None,
      on_reject_template_id: None,
    )
  let rendered = render.render(types.TemplatesListed([template]))
  assert string.contains(rendered, "linear")
  assert string.contains(rendered, "DESCRIPTION")
  assert string.contains(rendered, "one step")
}
