//// Tests for the shared domain models: strict enum decoding and round-trips.

import facet/models
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string

// ─── Strict enum decoding ───────────────────────────────────────────────────

pub fn task_level_accepts_known_values_test() {
  let assert Ok(models.Epic) =
    json.parse("\"epic\"", models.decode_task_level())
  let assert Ok(models.Ticket) =
    json.parse("\"ticket\"", models.decode_task_level())
  let assert Ok(models.TaskUnit) =
    json.parse("\"task\"", models.decode_task_level())
}

pub fn task_level_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"basic\"", models.decode_task_level())
}

pub fn priority_accepts_known_values_test() {
  let assert Ok(models.Low) = json.parse("\"low\"", models.decode_priority())
  let assert Ok(models.Medium) =
    json.parse("\"medium\"", models.decode_priority())
  let assert Ok(models.High) = json.parse("\"high\"", models.decode_priority())
  let assert Ok(models.Critical) =
    json.parse("\"critical\"", models.decode_priority())
}

pub fn priority_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"urgent\"", models.decode_priority())
}

pub fn task_status_accepts_known_values_test() {
  let assert Ok(models.Todo) =
    json.parse("\"todo\"", models.decode_task_status())
  let assert Ok(models.InProgress) =
    json.parse("\"in_progress\"", models.decode_task_status())
  let assert Ok(models.Done) =
    json.parse("\"done\"", models.decode_task_status())
  let assert Ok(models.Archived) =
    json.parse("\"archived\"", models.decode_task_status())
}

pub fn task_status_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"pending\"", models.decode_task_status())
}

pub fn execution_status_rejects_unknown_value_test() {
  let assert Error(_) =
    json.parse("\"paused\"", models.decode_execution_status())
}

pub fn step_status_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"running\"", models.decode_step_status())
}

pub fn node_type_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"magic\"", models.decode_node_type())
}

pub fn action_rejects_unknown_kind_test() {
  let assert Error(_) =
    json.parse("{\"kind\":\"teleport\"}", models.decode_action())
}

pub fn action_decodes_complete_test() {
  let assert Ok(models.FlowComplete) =
    json.parse("{\"kind\":\"flow_complete\"}", models.decode_action())
}

// ─── Round-trips ────────────────────────────────────────────────────────────

pub fn task_round_trip_test() {
  let task =
    models.Task(
      id: "task-1",
      short_id: "abc123",
      title: "Wire the client",
      description: "Talk to Crystalline",
      level: models.Ticket,
      priority: models.High,
      status: models.InProgress,
      tags: ["facet", "http"],
      parent_id: Some("parent-1"),
      flow_template_id: None,
      flow_instance_id: None,
      current_node_id: Some("node-1"),
      worktree: None,
      archived: False,
      created_at: 1_700_000_000,
      updated_at: 1_700_000_100,
    )

  let encoded = models.encode_task(task) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_task())
  assert decoded == task
}

pub fn flow_node_round_trip_test() {
  let node =
    models.FlowNode(
      id: "n1",
      name: "Research",
      node_type: models.Step,
      goal: "Understand the problem",
      prompt: Some("Research it"),
      child_ids: [],
      branch_rules: [],
      loop_config: None,
      agent_config: None,
      output_schema: None,
    )

  let encoded = models.encode_flow_node(node) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_flow_node())
  assert decoded == node
}

pub fn flow_template_round_trip_test() {
  let node =
    models.FlowNode(
      id: "n1",
      name: "Research",
      node_type: models.Step,
      goal: "Understand the problem",
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
      description: "research only",
      initial_node_id: "n1",
      nodes: dict.from_list([#("n1", node)]),
      transitions: [],
      on_done_template_id: None,
      on_reject_template_id: None,
    )

  let encoded = models.encode_flow_template(template) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_flow_template())
  assert decoded == template
}

pub fn step_execution_round_trip_test() {
  let step =
    models.StepExecution(
      id: "step-1",
      flow_instance_id: "flow-1",
      execution_state_id: "exec-1",
      node_id: "n1",
      task_id: "task-1",
      status: models.StepCompleted,
      prompt: Some("do it"),
      output: Some("done"),
      transition_result: None,
      model: Some("claude-sonnet-4"),
      input_tokens: 100,
      output_tokens: 42,
      cost: 0.25,
      duration_ms: 1234,
      session_id: None,
      created_at: 1,
      completed_at: Some(2),
    )

  let encoded = models.encode_step_execution(step) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_step_execution())
  assert decoded == step
}

pub fn session_log_round_trip_test() {
  let log =
    models.SessionLog(
      id: "log-1",
      step_execution_id: "step-1",
      task_id: "task-1",
      event_type: "text",
      payload: "{\"content\":\"hi\"}",
      sequence: 3,
      created_at: 1_700_000_000,
    )

  let encoded = models.encode_session_log(log) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_session_log())
  assert decoded == log
}

pub fn cost_decoder_accepts_integer_test() {
  // JSON numbers without a decimal point decode as floats too.
  assert Ok(0.0)
    == models.decode_json(
      "{\"id\":\"s\",\"status\":\"completed\",\"cost\":0}",
      models.decode_step_execution(),
    )
    |> result_map(fn(step) { step.cost })
}

fn result_map(result: Result(a, b), mapper: fn(a) -> c) -> Result(c, b) {
  case result {
    Ok(value) -> Ok(mapper(value))
    Error(error) -> Error(error)
  }
}

// ─── Task sections ──────────────────────────────────────────────────────────

pub fn section_type_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"summary\"", models.decode_section_type())
}

pub fn section_round_trip_test() {
  let section =
    models.Section(
      id: "sec-1",
      task_id: "task-1",
      section_type: models.TestingCriterion,
      content: "gleam test stays green",
      code_ref: None,
      order: 3,
    )
  let encoded = models.encode_section(section) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_section())
  assert decoded == section
}

pub fn section_create_encodes_type_and_content_test() {
  let body =
    models.SectionCreate(
      section_type: models.Goal,
      content: "Ship the release",
      code_ref: None,
    )
  assert models.encode_json(models.encode_section_create(body))
    == "{\"section_type\":\"goal\",\"content\":\"Ship the release\"}"
}

// ─── Code references ────────────────────────────────────────────────────────

pub fn section_with_code_ref_round_trips_test() {
  let code_ref =
    models.CodeRef(
      path: "src/main.gleam",
      line_start: Some(10),
      line_end: Some(20),
      name: Some("main"),
      description: Some("entry point"),
    )
  let section =
    models.Section(
      id: "sec-2",
      task_id: "task-1",
      section_type: models.Context,
      content: "src/main.gleam",
      code_ref: Some(code_ref),
      order: 2,
    )
  let encoded = models.encode_section(section) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_section())
  assert decoded == section
}

pub fn section_create_includes_code_ref_when_present_test() {
  let body =
    models.SectionCreate(
      section_type: models.DesiredBehavior,
      content: "guard the path",
      code_ref: Some(models.CodeRef(
        path: "src/a.gleam",
        line_start: Some(3),
        line_end: None,
        name: None,
        description: None,
      )),
    )
  assert models.encode_json(models.encode_section_create(body))
    == "{\"code_ref\":{\"path\":\"src/a.gleam\",\"line_start\":3,\"line_end\":null,\"name\":null,\"description\":null},\"section_type\":\"desired_behavior\",\"content\":\"guard the path\"}"
}

pub fn code_ref_clear_encodes_null_test() {
  assert models.encode_json(models.encode_code_ref_clear())
    == "{\"code_ref\":null}"
}

pub fn code_ref_decoder_rejects_a_ref_without_path_test() {
  let assert Error(_) =
    json.parse("{\"line_start\":1}", models.decode_code_ref())
}

// ─── Projects ───────────────────────────────────────────────────────────────

pub fn project_round_trip_test() {
  let project =
    models.Project(
      id: "proj-1",
      slug: "acme",
      name: "Acme",
      description: "the workspace",
      created_at: 1,
      updated_at: 2,
    )
  let encoded = models.encode_project(project) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_project())
  assert decoded == project
}

pub fn project_create_encodes_slug_and_name_test() {
  let body = models.ProjectCreate(slug: "acme", name: "Acme")
  assert models.encode_json(models.encode_project_create(body))
    == "{\"slug\":\"acme\",\"name\":\"Acme\"}"
}

// ─── Artifacts ──────────────────────────────────────────────────────────────

pub fn artifact_round_trips_arbitrary_json_content_test() {
  let artifact =
    models.Artifact(
      id: "art-1",
      task_id: "task-1",
      logical_name: "plan.json",
      content: json_value("{\"steps\":[1,2],\"done\":false,\"note\":null}"),
      created_at: 1,
      updated_at: 2,
    )
  let encoded = models.encode_artifact(artifact) |> models.encode_json
  let assert Ok(decoded) = json.parse(encoded, models.decode_artifact())
  assert decoded.id == artifact.id
  assert decoded.logical_name == artifact.logical_name
  // Key order is not part of the contract; the values must survive intact.
  let rendered = models.encode_json(decoded.content)
  assert string.contains(rendered, "\"steps\":[1,2]")
  assert string.contains(rendered, "\"done\":false")
  assert string.contains(rendered, "\"note\":null")
}

pub fn json_value_decoder_accepts_every_json_shape_test() {
  assert json_value("42") |> models.encode_json == "42"
  assert json_value("1.5") |> models.encode_json == "1.5"
  assert json_value("\"text\"") |> models.encode_json == "\"text\""
  assert json_value("true") |> models.encode_json == "true"
  assert json_value("null") |> models.encode_json == "null"
  assert json_value("[1,true,null]") |> models.encode_json == "[1,true,null]"
}

pub fn artifact_put_body_wraps_content_test() {
  let body = models.ArtifactPut(content: json_value("[1,2]"))
  assert models.encode_json(models.encode_artifact_put(body))
    == "{\"content\":[1,2]}"
}

// ─── Task path ──────────────────────────────────────────────────────────────

pub fn task_path_decodes_root_to_task_order_test() {
  let payload =
    "{\"path\":["
    <> task_with_parent("task-1", "Root", "null")
    <> ","
    <> task_with_parent("task-2", "Middle", "\"task-1\"")
    <> ","
    <> task_with_parent("task-3", "Leaf", "\"task-2\"")
    <> "]}"
  let assert Ok(path) = models.decode_json(payload, models.decode_task_path())
  assert list.map(path, fn(task) { task.id }) == ["task-1", "task-2", "task-3"]
  let assert Ok(leaf) = list.last(path)
  assert leaf.parent_id == Some("task-2")
}

pub fn task_path_requires_the_path_field_test() {
  let assert Error(_) =
    models.decode_json("{\"tasks\":[]}", models.decode_task_path())
}

fn json_value(raw: String) -> json.Json {
  let assert Ok(value) = models.decode_json(raw, models.json_value_decoder())
  value
}

fn task_with_parent(id: String, title: String, parent: String) -> String {
  "{\"id\":\""
  <> id
  <> "\",\"short_id\":\"s\",\"title\":\""
  <> title
  <> "\",\"description\":\"\",\"level\":\"ticket\",\"priority\":\"medium\",\"status\":\"todo\",\"tags\":[],\"parent_id\":"
  <> parent
  <> ",\"archived\":false,\"created_at\":1,\"updated_at\":2}"
}
