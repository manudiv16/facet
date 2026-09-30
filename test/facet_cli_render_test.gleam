//// Tests for structured output rendering (human-readable + JSON).

import facet/cli/render
import facet/cli/types
import facet/models
import gleam/dict
import gleam/option.{type Option, None, Some}
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

/// The engine's execution summary, as it arrives in the step envelopes.
fn running_summary() -> models.ExecutionSummary {
  models.ExecutionSummary(
    id: "exec-1",
    instance_id: "flow-1",
    task_id: "task-1",
    status: models.ExecRunning,
    current_node_id: Some("node-2"),
    started_at: Some(5),
    completed_at: None,
  )
}

fn step(action: models.Action) -> models.ExecutionStep {
  models.ExecutionStep(execution: running_summary(), action: action)
}

pub fn flow_started_renders_instance_and_status_test() {
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
  let instance =
    models.FlowInstance(
      id: "flow-1",
      template_id: "linear",
      task_id: "task-1",
      nodes: dict.from_list([#("n1", node)]),
      transitions: [],
      initial_node_id: "n1",
      on_done_template_id: None,
      on_reject_template_id: None,
    )
  let started =
    models.FlowInstantiation(
      instance: instance,
      execution: models.ExecutionSummary(
        id: "exec-1",
        instance_id: "flow-1",
        task_id: "task-1",
        status: models.ExecPending,
        current_node_id: None,
        started_at: None,
        completed_at: None,
      ),
    )
  let rendered = render.render(types.FlowStarted(started))
  assert string.contains(rendered, "flow-1")
  assert string.contains(rendered, "pending")
  assert string.contains(rendered, "linear")
  assert string.contains(rendered, "n1")

  let json = render.render_json(types.FlowStarted(started))
  assert string.contains(json, "\"instance\":{\"id\":\"flow-1\"")
  assert string.contains(json, "\"execution\":{")
  assert string.contains(json, "\"status\":\"pending\"")
  assert string.contains(json, "\"instance_id\":\"flow-1\"")
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
  let output = types.FlowAdvanced(step(models.RunStep(node, "Do it now")))
  let rendered = render.render(output)
  assert string.contains(rendered, "run_step")
  assert string.contains(rendered, "flow-1")
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
  let rendered =
    render.render(types.FlowAdvanced(step(models.AwaitInput(node))))
  assert string.contains(rendered, "await_input")
  assert string.contains(rendered, "facet flow input flow-1 \"<text>\"")
}

pub fn flow_advance_complete_renders_test() {
  let rendered = render.render(types.FlowAdvanced(step(models.FlowComplete)))
  assert string.contains(rendered, "flow_complete")
  assert string.contains(rendered, "facet task show <task-id>")
}

pub fn flow_advance_error_renders_message_test() {
  let rendered =
    render.render(
      types.FlowAdvanced(step(models.ExecutionError("model blew up"))),
    )
  assert string.contains(rendered, "execution_error")
  assert string.contains(rendered, "flow-1")
  assert string.contains(rendered, "model blew up")
  assert string.contains(rendered, "facet flow reject flow-1 --reason")
}

pub fn step_completed_renders_the_next_action_test() {
  let output = types.StepCompleted("node-2", step(models.FlowComplete))
  let rendered = render.render(output)
  assert string.contains(rendered, "step completed: node-2")
  assert string.contains(rendered, "flow_complete")

  let json = render.render_json(output)
  assert string.contains(json, "\"step_id\":\"node-2\"")
  assert string.contains(json, "\"execution\":{")
  assert string.contains(json, "\"type\":\"flow_complete\"")
}

pub fn input_provided_renders_the_next_action_test() {
  let node =
    models.FlowNode(
      id: "node-3",
      name: "Implement",
      node_type: models.Step,
      goal: "Implement the feature",
      prompt: None,
      child_ids: [],
      branch_rules: [],
      loop_config: None,
      agent_config: None,
      output_schema: None,
    )
  let output = types.InputProvided(step(models.RunStep(node, "go")))
  let rendered = render.render(output)
  assert string.contains(rendered, "input provided for instance flow-1")
  assert string.contains(rendered, "run_step")

  let json = render.render_json(output)
  assert string.contains(json, "\"type\":\"run_step\"")
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

pub fn json_flow_advance_renders_the_engine_envelope_test() {
  let output = types.FlowAdvanced(step(models.FlowComplete))
  let rendered = render.render_json(output)
  assert rendered
    == "{\"execution\":{\"id\":\"exec-1\",\"instance_id\":\"flow-1\",\"task_id\":\"task-1\",\"status\":\"running\",\"current_node_id\":\"node-2\",\"started_at\":5,\"completed_at\":null},\"action\":{\"type\":\"flow_complete\"}}"
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

// ─── Task sections ──────────────────────────────────────────────────────────

pub fn empty_sections_renders_no_sections_test() {
  assert render.render(types.SectionsShown("task-1", []))
    == "sections of task-1:\nno sections"
}

pub fn json_sections_render_array_test() {
  let section =
    models.Section(
      id: "sec-1",
      task_id: "task-1",
      section_type: models.Goal,
      content: "Ship the release",
      code_ref: None,
      order: 1,
    )
  let rendered = render.render_json(types.SectionsShown("task-1", [section]))
  assert string.contains(rendered, "\"id\":\"sec-1\"")
  assert string.contains(rendered, "\"section_type\":\"goal\"")
  assert string.contains(rendered, "\"content\":\"Ship the release\"")
}

// ─── init / path / stop ─────────────────────────────────────────────────────

fn sample_project() -> models.Project {
  models.Project(
    id: "proj-1",
    slug: "acme",
    name: "Acme",
    description: "",
    created_at: 1,
    updated_at: 2,
  )
}

pub fn project_initialized_renders_scope_and_config_path_test() {
  let output =
    types.ProjectInitialized(
      sample_project(),
      "/home/u/.config/facet/config.json",
    )
  let rendered = render.render(output)
  assert string.contains(rendered, "acme")
  assert string.contains(rendered, "proj-1")
  assert string.contains(rendered, "/home/u/.config/facet/config.json")

  let json = render.render_json(output)
  assert string.contains(json, "\"slug\":\"acme\"")
  assert string.contains(
    json,
    "\"config_path\":\"/home/u/.config/facet/config.json\"",
  )
}

pub fn task_path_renders_breadcrumb_test() {
  let output =
    types.TaskPathShown("task-3", [
      path_task("task-1", "Root"),
      path_task("task-2", "Middle"),
      path_task("task-3", "Leaf"),
    ])
  let rendered = render.render(output)
  assert string.contains(rendered, "path to task-3:")
  assert string.contains(rendered, "task-1 Root > task-2 Middle > task-3 Leaf")

  let json = render.render_json(output)
  assert string.contains(json, "\"task_id\":\"task-3\"")
  assert string.contains(json, "\"id\":\"task-1\"")
  assert string.contains(json, "\"id\":\"task-3\"")
}

pub fn flow_cancelled_renders_status_test() {
  let state =
    models.ExecutionSummary(
      id: "state-1",
      instance_id: "flow-1",
      task_id: "task-1",
      status: models.ExecCancelled,
      current_node_id: None,
      started_at: Some(1),
      completed_at: Some(99),
    )
  let output = types.FlowCancelled("flow-1", state)
  let rendered = render.render(output)
  assert string.contains(rendered, "flow cancelled: flow-1")
  assert string.contains(rendered, "cancelled")

  let json = render.render_json(output)
  assert string.contains(json, "\"instance_id\":\"flow-1\"")
  assert string.contains(json, "\"status\":\"cancelled\"")
  assert string.contains(json, "\"completed_at\":99")
}

// ─── code references ────────────────────────────────────────────────────────

pub fn code_ref_added_renders_section_and_ref_test() {
  let section = code_ref_section(Some(sample_code_ref()))
  let output = types.CodeRefAdded(section)
  let rendered = render.render(output)
  assert string.contains(rendered, "code reference added (section sec-9)")
  assert string.contains(rendered, "src/main.gleam:10-20 (main)")
  assert string.contains(rendered, "context")

  let json = render.render_json(output)
  assert string.contains(json, "\"section_type\":\"context\"")
  assert string.contains(json, "\"path\":\"src/main.gleam\"")
  assert string.contains(json, "\"line_start\":10")
}

pub fn code_ref_cleared_renders_none_test() {
  let output = types.CodeRefCleared("sec-9", code_ref_section(None))
  let rendered = render.render(output)
  assert string.contains(rendered, "code reference cleared (section sec-9)")
  assert string.contains(rendered, "code ref: (none)")

  let json = render.render_json(output)
  assert string.contains(json, "\"section_id\":\"sec-9\"")
  assert string.contains(json, "\"code_ref\":null")
}

pub fn section_without_code_ref_renders_none_test() {
  let rendered = render.render(types.SectionCreated(code_ref_section(None)))
  assert string.contains(rendered, "code ref: (none)")
  let json = render.render_json(types.SectionCreated(code_ref_section(None)))
  assert string.contains(json, "\"code_ref\":null")
}

pub fn sections_table_shows_the_code_ref_test() {
  let output =
    types.SectionsShown("task-1", [
      code_ref_section(Some(sample_code_ref())),
      code_ref_section(None),
    ])
  let rendered = render.render(output)
  assert string.contains(rendered, "CODE REF")
  assert string.contains(rendered, "src/main.gleam:10-20 (main)")
  assert string.contains(rendered, "(none)")
}

// ─── artifacts ──────────────────────────────────────────────────────────────

pub fn artifacts_listed_renders_table_and_json_test() {
  let output = types.ArtifactsListed("task-1", [sample_artifact()])
  let rendered = render.render(output)
  assert string.contains(rendered, "artifacts of task-1:")
  assert string.contains(rendered, "plan.json")
  assert string.contains(rendered, "NAME")

  let json = render.render_json(output)
  assert string.contains(json, "\"task_id\":\"task-1\"")
  assert string.contains(json, "\"logical_name\":\"plan.json\"")
}

pub fn empty_artifact_list_renders_no_artifacts_test() {
  assert render.render(types.ArtifactsListed("task-1", []))
    == "artifacts of task-1:\nno artifacts"
}

pub fn artifact_renders_content_json_test() {
  let output = types.ArtifactShown(sample_artifact())
  let rendered = render.render(output)
  assert string.contains(rendered, "plan.json")
  assert string.contains(rendered, "{\"ok\":true}")

  let stored = render.render_json(types.ArtifactStored(sample_artifact()))
  assert string.contains(stored, "\"content\":{\"ok\":true}")

  let deleted = render.render_json(types.ArtifactDeleted("task-1", "plan.json"))
  assert string.contains(deleted, "\"logical_name\":\"plan.json\"")
  assert string.contains(deleted, "\"deleted\":true")
}

pub fn usage_lists_the_new_commands_test() {
  let usage = render.usage()
  assert string.contains(usage, "init <slug>")
  assert string.contains(usage, "path <task-id>")
  assert string.contains(usage, "stop <instance-id>")
  assert string.contains(usage, "task ref <id> <path>")
  assert string.contains(usage, "task unref <id> <section-id>")
  assert string.contains(usage, "artifact <task-id> put <name>")
  assert string.contains(usage, "--project <id|slug>")
}

// ─── fixtures ───────────────────────────────────────────────────────────────

fn path_task(id: String, title: String) -> models.Task {
  models.Task(
    id: id,
    short_id: "s",
    title: title,
    description: "",
    level: models.Ticket,
    priority: models.Medium,
    status: models.Todo,
    tags: [],
    parent_id: None,
    flow_template_id: None,
    flow_instance_id: None,
    current_node_id: None,
    worktree: None,
    archived: False,
    created_at: 1,
    updated_at: 2,
  )
}

fn sample_code_ref() -> models.CodeRef {
  models.CodeRef(
    path: "src/main.gleam",
    line_start: Some(10),
    line_end: Some(20),
    name: Some("main"),
    description: None,
  )
}

fn code_ref_section(code_ref: Option(models.CodeRef)) -> models.Section {
  models.Section(
    id: "sec-9",
    task_id: "task-1",
    section_type: models.Context,
    content: "src/main.gleam",
    code_ref: code_ref,
    order: 1,
  )
}

fn sample_artifact() -> models.Artifact {
  let assert Ok(content) =
    models.decode_json("{\"ok\":true}", models.json_value_decoder())
  models.Artifact(
    id: "art-1",
    task_id: "task-1",
    logical_name: "plan.json",
    content: content,
    created_at: 1,
    updated_at: 2,
  )
}
