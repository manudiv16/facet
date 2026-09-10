//// Tests for the shared domain models: strict enum decoding and round-trips.

import facet/models
import gleam/dict
import gleam/json
import gleam/option.{None, Some}

// ─── Strict enum decoding ───────────────────────────────────────────────────

pub fn task_level_accepts_known_values_test() {
  let assert Ok(models.Epic) = json.parse("\"epic\"", models.decode_task_level())
  let assert Ok(models.Ticket) = json.parse(
    "\"ticket\"",
    models.decode_task_level(),
  )
  let assert Ok(models.TaskUnit) = json.parse("\"task\"", models.decode_task_level())
}

pub fn task_level_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"basic\"", models.decode_task_level())
}

pub fn priority_accepts_known_values_test() {
  let assert Ok(models.Low) = json.parse("\"low\"", models.decode_priority())
  let assert Ok(models.Medium) = json.parse("\"medium\"", models.decode_priority())
  let assert Ok(models.High) = json.parse("\"high\"", models.decode_priority())
  let assert Ok(models.Critical) = json.parse(
    "\"critical\"",
    models.decode_priority(),
  )
}

pub fn priority_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"urgent\"", models.decode_priority())
}

pub fn task_status_accepts_known_values_test() {
  let assert Ok(models.Todo) = json.parse("\"todo\"", models.decode_task_status())
  let assert Ok(models.InProgress) = json.parse(
    "\"in_progress\"",
    models.decode_task_status(),
  )
  let assert Ok(models.Done) = json.parse("\"done\"", models.decode_task_status())
  let assert Ok(models.Archived) = json.parse(
    "\"archived\"",
    models.decode_task_status(),
  )
}

pub fn task_status_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"pending\"", models.decode_task_status())
}

pub fn execution_status_rejects_unknown_value_test() {
  let assert Error(_) = json.parse(
    "\"paused\"",
    models.decode_execution_status(),
  )
}

pub fn step_status_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"running\"", models.decode_step_status())
}

pub fn node_type_rejects_unknown_value_test() {
  let assert Error(_) = json.parse("\"magic\"", models.decode_node_type())
}

pub fn action_rejects_unknown_kind_test() {
  let assert Error(_) = json.parse("{\"kind\":\"teleport\"}", models.decode_action())
}

pub fn action_decodes_complete_test() {
  let assert Ok(models.FlowComplete) = json.parse(
    "{\"kind\":\"flow_complete\"}",
    models.decode_action(),
  )
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
  assert Ok(0.0) == models.decode_json(
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
