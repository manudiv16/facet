//// Shared domain models for the Crystalline HTTP API.
////
//// These types mirror the Crystalline wire format (`domain/*.gleam`). Every
//// enum decoder is strict: an unexpected value produces a decode `Error`
//// rather than a silent fallback, so a malformed payload can never become a
//// partially built value.
////
//// Each model has an `encode_*` function and a `decode_*` function. The
//// `decode_*` functions return a `decode.Decoder`; `*_decoder` aliases are
//// provided for callers that prefer that naming.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

// ─── Enums ──────────────────────────────────────────────────────────────────

/// Task granularity, mirroring Crystalline's `domain/task.Level`.
pub type TaskLevel {
  Epic
  Ticket
  TaskUnit
}

pub fn task_level_to_string(level: TaskLevel) -> String {
  case level {
    Epic -> "epic"
    Ticket -> "ticket"
    TaskUnit -> "task"
  }
}

pub fn task_level_from_string(value: String) -> Result(TaskLevel, String) {
  case value {
    "epic" -> Ok(Epic)
    "ticket" -> Ok(Ticket)
    "task" -> Ok(TaskUnit)
    _ -> Error("unknown task level: " <> value)
  }
}

pub fn encode_task_level(level: TaskLevel) -> json.Json {
  json.string(task_level_to_string(level))
}

pub fn decode_task_level() -> decode.Decoder(TaskLevel) {
  strict_enum(task_level_from_string, Epic, "TaskLevel")
}

pub fn task_level_decoder() -> decode.Decoder(TaskLevel) {
  decode_task_level()
}

/// Task priority, mirroring Crystalline's `domain/task.Priority`.
pub type Priority {
  Low
  Medium
  High
  Critical
}

pub fn priority_to_string(priority: Priority) -> String {
  case priority {
    Low -> "low"
    Medium -> "medium"
    High -> "high"
    Critical -> "critical"
  }
}

pub fn priority_from_string(value: String) -> Result(Priority, String) {
  case value {
    "low" -> Ok(Low)
    "medium" -> Ok(Medium)
    "high" -> Ok(High)
    "critical" -> Ok(Critical)
    _ -> Error("unknown priority: " <> value)
  }
}

pub fn encode_priority(priority: Priority) -> json.Json {
  json.string(priority_to_string(priority))
}

pub fn decode_priority() -> decode.Decoder(Priority) {
  strict_enum(priority_from_string, Low, "Priority")
}

pub fn priority_decoder() -> decode.Decoder(Priority) {
  decode_priority()
}

/// Task lifecycle status, mirroring Crystalline's `domain/task.TaskStatus`.
pub type TaskStatus {
  Todo
  InProgress
  Blocked
  Done
  Cancelled
  Archived
}

pub fn task_status_to_string(status: TaskStatus) -> String {
  case status {
    Todo -> "todo"
    InProgress -> "in_progress"
    Blocked -> "blocked"
    Done -> "done"
    Cancelled -> "cancelled"
    Archived -> "archived"
  }
}

pub fn task_status_from_string(value: String) -> Result(TaskStatus, String) {
  case value {
    "todo" -> Ok(Todo)
    "in_progress" -> Ok(InProgress)
    "blocked" -> Ok(Blocked)
    "done" -> Ok(Done)
    "cancelled" -> Ok(Cancelled)
    "archived" -> Ok(Archived)
    _ -> Error("unknown task status: " <> value)
  }
}

pub fn encode_task_status(status: TaskStatus) -> json.Json {
  json.string(task_status_to_string(status))
}

pub fn decode_task_status() -> decode.Decoder(TaskStatus) {
  strict_enum(task_status_from_string, Todo, "TaskStatus")
}

pub fn task_status_decoder() -> decode.Decoder(TaskStatus) {
  decode_task_status()
}

/// Execution lifecycle status, mirroring Crystalline's
/// `domain/execution.ExecutionStatus`.
pub type ExecutionStatus {
  ExecPending
  ExecRunning
  ExecAwaitingInput
  ExecCompleted
  ExecRejected
  ExecFailed
  ExecCancelled
}

pub fn execution_status_to_string(status: ExecutionStatus) -> String {
  case status {
    ExecPending -> "pending"
    ExecRunning -> "running"
    ExecAwaitingInput -> "awaiting_input"
    ExecCompleted -> "completed"
    ExecRejected -> "rejected"
    ExecFailed -> "failed"
    ExecCancelled -> "cancelled"
  }
}

pub fn execution_status_from_string(
  value: String,
) -> Result(ExecutionStatus, String) {
  case value {
    "pending" -> Ok(ExecPending)
    "running" -> Ok(ExecRunning)
    "awaiting_input" -> Ok(ExecAwaitingInput)
    "completed" -> Ok(ExecCompleted)
    "rejected" -> Ok(ExecRejected)
    "failed" -> Ok(ExecFailed)
    "cancelled" -> Ok(ExecCancelled)
    _ -> Error("unknown execution status: " <> value)
  }
}

pub fn encode_execution_status(status: ExecutionStatus) -> json.Json {
  json.string(execution_status_to_string(status))
}

pub fn decode_execution_status() -> decode.Decoder(ExecutionStatus) {
  strict_enum(execution_status_from_string, ExecPending, "ExecutionStatus")
}

pub fn execution_status_decoder() -> decode.Decoder(ExecutionStatus) {
  decode_execution_status()
}

/// Step lifecycle status, mirroring Crystalline's `domain/execution.StepStatus`.
pub type StepStatus {
  StepPending
  StepEntered
  StepInProgress
  StepCompleted
  StepFailed
  StepCancelled
}

pub fn step_status_to_string(status: StepStatus) -> String {
  case status {
    StepPending -> "pending"
    StepEntered -> "entered"
    StepInProgress -> "in_progress"
    StepCompleted -> "completed"
    StepFailed -> "failed"
    StepCancelled -> "cancelled"
  }
}

pub fn step_status_from_string(value: String) -> Result(StepStatus, String) {
  case value {
    "pending" -> Ok(StepPending)
    "entered" -> Ok(StepEntered)
    "in_progress" -> Ok(StepInProgress)
    "completed" -> Ok(StepCompleted)
    "failed" -> Ok(StepFailed)
    "cancelled" -> Ok(StepCancelled)
    _ -> Error("unknown step status: " <> value)
  }
}

pub fn encode_step_status(status: StepStatus) -> json.Json {
  json.string(step_status_to_string(status))
}

pub fn decode_step_status() -> decode.Decoder(StepStatus) {
  strict_enum(step_status_from_string, StepPending, "StepStatus")
}

pub fn step_status_decoder() -> decode.Decoder(StepStatus) {
  decode_step_status()
}

/// Flow node kind, mirroring Crystalline's `domain/flow.NodeType`.
pub type NodeType {
  Step
  Sequence
  Branch
  Loop
  Parallel
  HumanInput
}

pub fn node_type_to_string(node_type: NodeType) -> String {
  case node_type {
    Step -> "step"
    Sequence -> "sequence"
    Branch -> "branch"
    Loop -> "loop"
    Parallel -> "parallel"
    HumanInput -> "human_input"
  }
}

pub fn node_type_from_string(value: String) -> Result(NodeType, String) {
  case value {
    "step" -> Ok(Step)
    "sequence" -> Ok(Sequence)
    "branch" -> Ok(Branch)
    "loop" -> Ok(Loop)
    "parallel" -> Ok(Parallel)
    "human_input" -> Ok(HumanInput)
    _ -> Error("unknown node type: " <> value)
  }
}

pub fn encode_node_type(node_type: NodeType) -> json.Json {
  json.string(node_type_to_string(node_type))
}

pub fn decode_node_type() -> decode.Decoder(NodeType) {
  strict_enum(node_type_from_string, Step, "NodeType")
}

pub fn node_type_decoder() -> decode.Decoder(NodeType) {
  decode_node_type()
}

// ─── Projects ───────────────────────────────────────────────────────────────

/// A workspace. Tasks, sections and the artifact list are scoped to one
/// project through the `X-Crystalline-Project` header, which accepts a
/// project id or slug.
pub type Project {
  Project(
    id: String,
    slug: String,
    name: String,
    description: String,
    created_at: Int,
    updated_at: Int,
  )
}

pub fn encode_project(project: Project) -> json.Json {
  json.object([
    #("id", json.string(project.id)),
    #("slug", json.string(project.slug)),
    #("name", json.string(project.name)),
    #("description", json.string(project.description)),
    #("created_at", json.int(project.created_at)),
    #("updated_at", json.int(project.updated_at)),
  ])
}

pub fn decode_project() -> decode.Decoder(Project) {
  use id <- decode.field("id", decode.string)
  use slug <- decode.field("slug", decode.string)
  use name <- decode.optional_field("name", "", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use created_at <- decode.optional_field("created_at", 0, decode.int)
  use updated_at <- decode.optional_field("updated_at", 0, decode.int)
  decode.success(Project(
    id:,
    slug:,
    name:,
    description:,
    created_at:,
    updated_at:,
  ))
}

pub fn project_decoder() -> decode.Decoder(Project) {
  decode_project()
}

/// Body for `POST /api/v1/projects`.
pub type ProjectCreate {
  ProjectCreate(slug: String, name: String)
}

pub fn encode_project_create(body: ProjectCreate) -> json.Json {
  json.object([
    #("slug", json.string(body.slug)),
    #("name", json.string(body.name)),
  ])
}

// ─── Artifacts ──────────────────────────────────────────────────────────────

/// A JSON document stored under a task-scoped logical name. The content is
/// arbitrary JSON and round-trips unchanged.
pub type Artifact {
  Artifact(
    id: String,
    task_id: String,
    logical_name: String,
    content: json.Json,
    created_at: Int,
    updated_at: Int,
  )
}

pub fn encode_artifact(artifact: Artifact) -> json.Json {
  json.object([
    #("id", json.string(artifact.id)),
    #("task_id", json.string(artifact.task_id)),
    #("logical_name", json.string(artifact.logical_name)),
    #("content", artifact.content),
    #("created_at", json.int(artifact.created_at)),
    #("updated_at", json.int(artifact.updated_at)),
  ])
}

pub fn decode_artifact() -> decode.Decoder(Artifact) {
  use id <- decode.field("id", decode.string)
  use task_id <- decode.optional_field("task_id", "", decode.string)
  use logical_name <- decode.optional_field("logical_name", "", decode.string)
  use content <- decode.field("content", json_value_decoder())
  use created_at <- decode.optional_field("created_at", 0, decode.int)
  use updated_at <- decode.optional_field("updated_at", 0, decode.int)
  decode.success(Artifact(
    id:,
    task_id:,
    logical_name:,
    content:,
    created_at:,
    updated_at:,
  ))
}

pub fn artifact_decoder() -> decode.Decoder(Artifact) {
  decode_artifact()
}

/// Body for `PUT /api/v1/tasks/:task_id/artifacts/:logical_name`.
pub type ArtifactPut {
  ArtifactPut(content: json.Json)
}

pub fn encode_artifact_put(body: ArtifactPut) -> json.Json {
  json.object([#("content", body.content)])
}

/// Decode any JSON value — string, number, bool, null, array or object —
/// into `gleam/json`'s `Json` so it can be re-emitted unchanged.
pub fn json_value_decoder() -> decode.Decoder(json.Json) {
  use <- decode.recursive
  decode.one_of(decode.string |> decode.map(json.string), [
    decode.int |> decode.map(json.int),
    decode.float |> decode.map(json.float),
    decode.bool |> decode.map(json.bool),
    decode.list(json_value_decoder())
      |> decode.map(fn(values) { json.array(values, fn(value) { value }) }),
    decode.dict(decode.string, json_value_decoder())
      |> decode.map(fn(values) {
        json.dict(values, fn(key) { key }, fn(value) { value })
      }),
    decode.optional(decode.string)
      |> decode.map(fn(value) {
        case value {
          Some(text) -> json.string(text)
          None -> json.null()
        }
      }),
  ])
}

// ─── Flow models ────────────────────────────────────────────────────────────

pub type BranchRule {
  BranchRule(condition: String, target_id: String)
}

pub fn encode_branch_rule(rule: BranchRule) -> json.Json {
  json.object([
    #("condition", json.string(rule.condition)),
    #("target_id", json.string(rule.target_id)),
  ])
}

pub fn decode_branch_rule() -> decode.Decoder(BranchRule) {
  use condition <- decode.field("condition", decode.string)
  use target_id <- decode.field("target_id", decode.string)
  decode.success(BranchRule(condition:, target_id:))
}

pub fn branch_rule_decoder() -> decode.Decoder(BranchRule) {
  decode_branch_rule()
}

pub type LoopConfig {
  LoopConfig(
    max_iterations: Option(Int),
    exit_condition: Option(String),
    child_ids: List(String),
  )
}

pub fn encode_loop_config(config: LoopConfig) -> json.Json {
  json.object([
    #("max_iterations", json.nullable(config.max_iterations, json.int)),
    #("exit_condition", json.nullable(config.exit_condition, json.string)),
    #("child_ids", json.array(config.child_ids, json.string)),
  ])
}

pub fn decode_loop_config() -> decode.Decoder(LoopConfig) {
  use max_iterations <- decode.optional_field(
    "max_iterations",
    None,
    decode.optional(decode.int),
  )
  use exit_condition <- decode.optional_field(
    "exit_condition",
    None,
    decode.optional(decode.string),
  )
  use child_ids <- decode.optional_field(
    "child_ids",
    [],
    decode.list(decode.string),
  )
  decode.success(LoopConfig(max_iterations:, exit_condition:, child_ids:))
}

pub fn loop_config_decoder() -> decode.Decoder(LoopConfig) {
  decode_loop_config()
}

pub type AgentConfig {
  AgentConfig(
    model: String,
    fallback_model: Option(String),
    system_prompt: Option(String),
    allowed_tools: List(String),
    disallowed_tools: List(String),
    permission_mode: String,
    max_budget_usd: Float,
  )
}

pub fn encode_agent_config(config: AgentConfig) -> json.Json {
  json.object([
    #("model", json.string(config.model)),
    #("fallback_model", json.nullable(config.fallback_model, json.string)),
    #("system_prompt", json.nullable(config.system_prompt, json.string)),
    #("allowed_tools", json.array(config.allowed_tools, json.string)),
    #("disallowed_tools", json.array(config.disallowed_tools, json.string)),
    #("permission_mode", json.string(config.permission_mode)),
    #("max_budget_usd", json.float(config.max_budget_usd)),
  ])
}

pub fn decode_agent_config() -> decode.Decoder(AgentConfig) {
  use model <- decode.field("model", decode.string)
  use fallback_model <- decode.optional_field(
    "fallback_model",
    None,
    decode.optional(decode.string),
  )
  use system_prompt <- decode.optional_field(
    "system_prompt",
    None,
    decode.optional(decode.string),
  )
  use allowed_tools <- decode.optional_field(
    "allowed_tools",
    [],
    decode.list(decode.string),
  )
  use disallowed_tools <- decode.optional_field(
    "disallowed_tools",
    [],
    decode.list(decode.string),
  )
  use permission_mode <- decode.optional_field(
    "permission_mode",
    "default",
    decode.string,
  )
  use max_budget_usd <- decode.optional_field(
    "max_budget_usd",
    0.0,
    decode_float(),
  )
  decode.success(AgentConfig(
    model:,
    fallback_model:,
    system_prompt:,
    allowed_tools:,
    disallowed_tools:,
    permission_mode:,
    max_budget_usd:,
  ))
}

pub fn agent_config_decoder() -> decode.Decoder(AgentConfig) {
  decode_agent_config()
}

/// A node in a flow graph. Named `FlowNode` here to distinguish it from
/// unrelated node types in a consumer application.
pub type FlowNode {
  FlowNode(
    id: String,
    name: String,
    node_type: NodeType,
    goal: String,
    prompt: Option(String),
    child_ids: List(String),
    branch_rules: List(BranchRule),
    loop_config: Option(LoopConfig),
    agent_config: Option(AgentConfig),
    output_schema: Option(String),
  )
}

pub fn encode_flow_node(node: FlowNode) -> json.Json {
  json.object([
    #("id", json.string(node.id)),
    #("name", json.string(node.name)),
    #("node_type", encode_node_type(node.node_type)),
    #("goal", json.string(node.goal)),
    #("prompt", json.nullable(node.prompt, json.string)),
    #("child_ids", json.array(node.child_ids, json.string)),
    #("branch_rules", json.array(node.branch_rules, encode_branch_rule)),
    #("loop_config", json.nullable(node.loop_config, encode_loop_config)),
    #("agent_config", json.nullable(node.agent_config, encode_agent_config)),
    #("output_schema", json.nullable(node.output_schema, json.string)),
  ])
}

pub fn decode_flow_node() -> decode.Decoder(FlowNode) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use node_type <- decode.field("node_type", decode_node_type())
  use goal <- decode.optional_field("goal", "", decode.string)
  use prompt <- decode.optional_field(
    "prompt",
    None,
    decode.optional(decode.string),
  )
  use child_ids <- decode.optional_field(
    "child_ids",
    [],
    decode.list(decode.string),
  )
  use branch_rules <- decode.optional_field(
    "branch_rules",
    [],
    decode.list(decode_branch_rule()),
  )
  use loop_config <- decode.optional_field(
    "loop_config",
    None,
    decode.optional(decode_loop_config()),
  )
  use agent_config <- decode.optional_field(
    "agent_config",
    None,
    decode.optional(decode_agent_config()),
  )
  use output_schema <- decode.optional_field(
    "output_schema",
    None,
    decode.optional(decode.string),
  )
  decode.success(FlowNode(
    id:,
    name:,
    node_type:,
    goal:,
    prompt:,
    child_ids:,
    branch_rules:,
    loop_config:,
    agent_config:,
    output_schema:,
  ))
}

pub fn flow_node_decoder() -> decode.Decoder(FlowNode) {
  decode_flow_node()
}

pub type FlowTransition {
  FlowTransition(
    id: String,
    from_id: String,
    to_id: String,
    condition: Option(String),
    label: Option(String),
  )
}

/// Alias kept for parity with Crystalline's `domain/flow.Transition`.
pub type Transition =
  FlowTransition

pub fn encode_flow_transition(transition: FlowTransition) -> json.Json {
  json.object([
    #("id", json.string(transition.id)),
    #("from_id", json.string(transition.from_id)),
    #("to_id", json.string(transition.to_id)),
    #("condition", json.nullable(transition.condition, json.string)),
    #("label", json.nullable(transition.label, json.string)),
  ])
}

pub fn decode_flow_transition() -> decode.Decoder(FlowTransition) {
  use id <- decode.field("id", decode.string)
  use from_id <- decode.field("from_id", decode.string)
  use to_id <- decode.field("to_id", decode.string)
  use condition <- decode.optional_field(
    "condition",
    None,
    decode.optional(decode.string),
  )
  use label <- decode.optional_field(
    "label",
    None,
    decode.optional(decode.string),
  )
  decode.success(FlowTransition(id:, from_id:, to_id:, condition:, label:))
}

pub fn flow_transition_decoder() -> decode.Decoder(FlowTransition) {
  decode_flow_transition()
}

pub type FlowTemplate {
  FlowTemplate(
    id: String,
    name: String,
    description: String,
    initial_node_id: String,
    nodes: Dict(String, FlowNode),
    transitions: List(FlowTransition),
    on_done_template_id: Option(String),
    on_reject_template_id: Option(String),
  )
}

pub fn encode_flow_template(template: FlowTemplate) -> json.Json {
  json.object([
    #("id", json.string(template.id)),
    #("name", json.string(template.name)),
    #("description", json.string(template.description)),
    #("initial_node_id", json.string(template.initial_node_id)),
    #("nodes", encode_node_dict(template.nodes)),
    #("transitions", json.array(template.transitions, encode_flow_transition)),
    #(
      "on_done_template_id",
      json.nullable(template.on_done_template_id, json.string),
    ),
    #(
      "on_reject_template_id",
      json.nullable(template.on_reject_template_id, json.string),
    ),
  ])
}

pub fn decode_flow_template() -> decode.Decoder(FlowTemplate) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use initial_node_id <- decode.optional_field(
    "initial_node_id",
    "",
    decode.string,
  )
  use nodes <- decode.optional_field(
    "nodes",
    dict.new(),
    decode.dict(decode.string, decode_flow_node()),
  )
  use transitions <- decode.optional_field(
    "transitions",
    [],
    decode.list(decode_flow_transition()),
  )
  use on_done_template_id <- decode.optional_field(
    "on_done_template_id",
    None,
    decode.optional(decode.string),
  )
  use on_reject_template_id <- decode.optional_field(
    "on_reject_template_id",
    None,
    decode.optional(decode.string),
  )
  decode.success(FlowTemplate(
    id:,
    name:,
    description:,
    initial_node_id:,
    nodes:,
    transitions:,
    on_done_template_id:,
    on_reject_template_id:,
  ))
}

pub fn flow_template_decoder() -> decode.Decoder(FlowTemplate) {
  decode_flow_template()
}

pub type FlowInstance {
  FlowInstance(
    id: String,
    template_id: String,
    task_id: String,
    nodes: Dict(String, FlowNode),
    transitions: List(FlowTransition),
    initial_node_id: String,
    on_done_template_id: Option(String),
    on_reject_template_id: Option(String),
  )
}

pub fn encode_flow_instance(instance: FlowInstance) -> json.Json {
  json.object([
    #("id", json.string(instance.id)),
    #("template_id", json.string(instance.template_id)),
    #("task_id", json.string(instance.task_id)),
    #("nodes", encode_node_dict(instance.nodes)),
    #("transitions", json.array(instance.transitions, encode_flow_transition)),
    #("initial_node_id", json.string(instance.initial_node_id)),
    #(
      "on_done_template_id",
      json.nullable(instance.on_done_template_id, json.string),
    ),
    #(
      "on_reject_template_id",
      json.nullable(instance.on_reject_template_id, json.string),
    ),
  ])
}

pub fn decode_flow_instance() -> decode.Decoder(FlowInstance) {
  use id <- decode.field("id", decode.string)
  use template_id <- decode.optional_field("template_id", "", decode.string)
  use task_id <- decode.optional_field("task_id", "", decode.string)
  use nodes <- decode.optional_field(
    "nodes",
    dict.new(),
    decode.dict(decode.string, decode_flow_node()),
  )
  use transitions <- decode.optional_field(
    "transitions",
    [],
    decode.list(decode_flow_transition()),
  )
  use initial_node_id <- decode.optional_field(
    "initial_node_id",
    "",
    decode.string,
  )
  use on_done_template_id <- decode.optional_field(
    "on_done_template_id",
    None,
    decode.optional(decode.string),
  )
  use on_reject_template_id <- decode.optional_field(
    "on_reject_template_id",
    None,
    decode.optional(decode.string),
  )
  decode.success(FlowInstance(
    id:,
    template_id:,
    task_id:,
    nodes:,
    transitions:,
    initial_node_id:,
    on_done_template_id:,
    on_reject_template_id:,
  ))
}

pub fn flow_instance_decoder() -> decode.Decoder(FlowInstance) {
  decode_flow_instance()
}

// ─── Task model ─────────────────────────────────────────────────────────────

pub type Task {
  Task(
    id: String,
    short_id: String,
    title: String,
    description: String,
    level: TaskLevel,
    priority: Priority,
    status: TaskStatus,
    tags: List(String),
    parent_id: Option(String),
    flow_template_id: Option(String),
    flow_instance_id: Option(String),
    current_node_id: Option(String),
    worktree: Option(String),
    archived: Bool,
    created_at: Int,
    updated_at: Int,
  )
}

pub fn encode_task(task: Task) -> json.Json {
  json.object([
    #("id", json.string(task.id)),
    #("short_id", json.string(task.short_id)),
    #("title", json.string(task.title)),
    #("description", json.string(task.description)),
    #("level", encode_task_level(task.level)),
    #("priority", encode_priority(task.priority)),
    #("status", encode_task_status(task.status)),
    #("tags", json.array(task.tags, json.string)),
    #("parent_id", json.nullable(task.parent_id, json.string)),
    #("flow_template_id", json.nullable(task.flow_template_id, json.string)),
    #("flow_instance_id", json.nullable(task.flow_instance_id, json.string)),
    #("current_node_id", json.nullable(task.current_node_id, json.string)),
    #("worktree", json.nullable(task.worktree, json.string)),
    #("archived", json.bool(task.archived)),
    #("created_at", json.int(task.created_at)),
    #("updated_at", json.int(task.updated_at)),
  ])
}

pub fn decode_task() -> decode.Decoder(Task) {
  use id <- decode.field("id", decode.string)
  use short_id <- decode.optional_field("short_id", "", decode.string)
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use level <- decode.field("level", decode_task_level())
  use priority <- decode.field("priority", decode_priority())
  use status <- decode.field("status", decode_task_status())
  use tags <- decode.optional_field("tags", [], decode.list(decode.string))
  use parent_id <- decode.optional_field(
    "parent_id",
    None,
    decode.optional(decode.string),
  )
  use flow_template_id <- decode.optional_field(
    "flow_template_id",
    None,
    decode.optional(decode.string),
  )
  use flow_instance_id <- decode.optional_field(
    "flow_instance_id",
    None,
    decode.optional(decode.string),
  )
  use current_node_id <- decode.optional_field(
    "current_node_id",
    None,
    decode.optional(decode.string),
  )
  use worktree <- decode.optional_field(
    "worktree",
    None,
    decode.optional(decode.string),
  )
  use archived <- decode.optional_field("archived", False, decode.bool)
  use created_at <- decode.optional_field("created_at", 0, decode.int)
  use updated_at <- decode.optional_field("updated_at", 0, decode.int)
  decode.success(Task(
    id:,
    short_id:,
    title:,
    description:,
    level:,
    priority:,
    status:,
    tags:,
    parent_id:,
    flow_template_id:,
    flow_instance_id:,
    current_node_id:,
    worktree:,
    archived:,
    created_at:,
    updated_at:,
  ))
}

pub fn task_decoder() -> decode.Decoder(Task) {
  decode_task()
}

/// `GET /api/v1/tasks/:id/path` answers `{"path": [root, …, task]}`; this
/// yields the ordered ancestor chain root-first.
pub fn decode_task_path() -> decode.Decoder(List(Task)) {
  use path <- decode.field("path", decode.list(decode_task()))
  decode.success(path)
}

pub fn task_path_decoder() -> decode.Decoder(List(Task)) {
  decode_task_path()
}

// ─── Task sections ──────────────────────────────────────────────────────────

/// The role a section plays in a task's description. Mirrors the
/// `section_type` column of Crystalline's sections table (crystalline#16).
pub type SectionType {
  Goal
  Context
  CurrentBehavior
  DesiredBehavior
  ChecklistItem
  TestingCriterion
  Constraint
  AntiPattern
  FailureTest
}

pub fn section_type_to_string(section_type: SectionType) -> String {
  case section_type {
    Goal -> "goal"
    Context -> "context"
    CurrentBehavior -> "current_behavior"
    DesiredBehavior -> "desired_behavior"
    ChecklistItem -> "checklist_item"
    TestingCriterion -> "testing_criterion"
    Constraint -> "constraint"
    AntiPattern -> "anti_pattern"
    FailureTest -> "failure_test"
  }
}

pub fn section_type_from_string(value: String) -> Result(SectionType, String) {
  case value {
    "goal" -> Ok(Goal)
    "context" -> Ok(Context)
    "current_behavior" -> Ok(CurrentBehavior)
    "desired_behavior" -> Ok(DesiredBehavior)
    "checklist_item" -> Ok(ChecklistItem)
    "testing_criterion" -> Ok(TestingCriterion)
    "constraint" -> Ok(Constraint)
    "anti_pattern" -> Ok(AntiPattern)
    "failure_test" -> Ok(FailureTest)
    _ -> Error(value)
  }
}

pub fn encode_section_type(section_type: SectionType) -> json.Json {
  json.string(section_type_to_string(section_type))
}

pub fn decode_section_type() -> decode.Decoder(SectionType) {
  strict_enum(section_type_from_string, Goal, "SectionType")
}

pub fn section_type_decoder() -> decode.Decoder(SectionType) {
  decode_section_type()
}

/// A file reference attached to a section: the section is the entity, and a
/// code reference is one of its fields (there is no separate code-ref
/// resource in the engine).
pub type CodeRef {
  CodeRef(
    path: String,
    line_start: Option(Int),
    line_end: Option(Int),
    name: Option(String),
    description: Option(String),
  )
}

pub fn encode_code_ref(code_ref: CodeRef) -> json.Json {
  json.object([
    #("path", json.string(code_ref.path)),
    #("line_start", json.nullable(code_ref.line_start, json.int)),
    #("line_end", json.nullable(code_ref.line_end, json.int)),
    #("name", json.nullable(code_ref.name, json.string)),
    #("description", json.nullable(code_ref.description, json.string)),
  ])
}

pub fn decode_code_ref() -> decode.Decoder(CodeRef) {
  use path <- decode.field("path", decode.string)
  use line_start <- decode.optional_field(
    "line_start",
    None,
    decode.optional(decode.int),
  )
  use line_end <- decode.optional_field(
    "line_end",
    None,
    decode.optional(decode.int),
  )
  use name <- decode.optional_field(
    "name",
    None,
    decode.optional(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  decode.success(CodeRef(path:, line_start:, line_end:, name:, description:))
}

pub fn code_ref_decoder() -> decode.Decoder(CodeRef) {
  decode_code_ref()
}

/// A structured part of a task's description. `code_ref` is `None` when the
/// section carries prose only.
pub type Section {
  Section(
    id: String,
    task_id: String,
    section_type: SectionType,
    content: String,
    code_ref: Option(CodeRef),
    order: Int,
  )
}

pub fn encode_section(section: Section) -> json.Json {
  json.object([
    #("id", json.string(section.id)),
    #("task_id", json.string(section.task_id)),
    #("section_type", encode_section_type(section.section_type)),
    #("content", json.string(section.content)),
    #("code_ref", json.nullable(section.code_ref, encode_code_ref)),
    #("order", json.int(section.order)),
  ])
}

pub fn decode_section() -> decode.Decoder(Section) {
  use id <- decode.field("id", decode.string)
  use task_id <- decode.optional_field("task_id", "", decode.string)
  use section_type <- decode.field("section_type", decode_section_type())
  use content <- decode.optional_field("content", "", decode.string)
  use code_ref <- decode.optional_field(
    "code_ref",
    None,
    decode.optional(decode_code_ref()),
  )
  use order <- decode.optional_field("order", 0, decode.int)
  decode.success(Section(
    id:,
    task_id:,
    section_type:,
    content:,
    code_ref:,
    order:,
  ))
}

pub fn section_decoder() -> decode.Decoder(Section) {
  decode_section()
}

// ─── Execution models ───────────────────────────────────────────────────────

pub type StepExecution {
  StepExecution(
    id: String,
    flow_instance_id: String,
    execution_state_id: String,
    node_id: String,
    task_id: String,
    status: StepStatus,
    prompt: Option(String),
    output: Option(String),
    transition_result: Option(String),
    model: Option(String),
    input_tokens: Int,
    output_tokens: Int,
    cost: Float,
    duration_ms: Int,
    session_id: Option(String),
    created_at: Int,
    completed_at: Option(Int),
  )
}

pub fn encode_step_execution(step: StepExecution) -> json.Json {
  json.object([
    #("id", json.string(step.id)),
    #("flow_instance_id", json.string(step.flow_instance_id)),
    #("execution_state_id", json.string(step.execution_state_id)),
    #("node_id", json.string(step.node_id)),
    #("task_id", json.string(step.task_id)),
    #("status", encode_step_status(step.status)),
    #("prompt", json.nullable(step.prompt, json.string)),
    #("output", json.nullable(step.output, json.string)),
    #("transition_result", json.nullable(step.transition_result, json.string)),
    #("model", json.nullable(step.model, json.string)),
    #("input_tokens", json.int(step.input_tokens)),
    #("output_tokens", json.int(step.output_tokens)),
    #("cost", json.float(step.cost)),
    #("duration_ms", json.int(step.duration_ms)),
    #("session_id", json.nullable(step.session_id, json.string)),
    #("created_at", json.int(step.created_at)),
    #("completed_at", json.nullable(step.completed_at, json.int)),
  ])
}

pub fn decode_step_execution() -> decode.Decoder(StepExecution) {
  use id <- decode.field("id", decode.string)
  use flow_instance_id <- decode.optional_field(
    "flow_instance_id",
    "",
    decode.string,
  )
  use execution_state_id <- decode.optional_field(
    "execution_state_id",
    "",
    decode.string,
  )
  use node_id <- decode.optional_field("node_id", "", decode.string)
  use task_id <- decode.optional_field("task_id", "", decode.string)
  use status <- decode.field("status", decode_step_status())
  use prompt <- decode.optional_field(
    "prompt",
    None,
    decode.optional(decode.string),
  )
  use output <- decode.optional_field(
    "output",
    None,
    decode.optional(decode.string),
  )
  use transition_result <- decode.optional_field(
    "transition_result",
    None,
    decode.optional(decode.string),
  )
  use model <- decode.optional_field(
    "model",
    None,
    decode.optional(decode.string),
  )
  use input_tokens <- decode.optional_field("input_tokens", 0, decode.int)
  use output_tokens <- decode.optional_field("output_tokens", 0, decode.int)
  use cost <- decode.optional_field("cost", 0.0, decode_float())
  use duration_ms <- decode.optional_field("duration_ms", 0, decode.int)
  use session_id <- decode.optional_field(
    "session_id",
    None,
    decode.optional(decode.string),
  )
  use created_at <- decode.optional_field("created_at", 0, decode.int)
  use completed_at <- decode.optional_field(
    "completed_at",
    None,
    decode.optional(decode.int),
  )
  decode.success(StepExecution(
    id:,
    flow_instance_id:,
    execution_state_id:,
    node_id:,
    task_id:,
    status:,
    prompt:,
    output:,
    transition_result:,
    model:,
    input_tokens:,
    output_tokens:,
    cost:,
    duration_ms:,
    session_id:,
    created_at:,
    completed_at:,
  ))
}

pub fn step_execution_decoder() -> decode.Decoder(StepExecution) {
  decode_step_execution()
}

pub type ExecutionState {
  ExecutionState(
    id: String,
    flow_instance: FlowInstance,
    task_id: String,
    status: ExecutionStatus,
    current_node_id: Option(String),
    step_history: List(StepExecution),
    loop_counters: Dict(String, Int),
    variables: Dict(String, String),
    parallel_active: List(String),
    started_at: Option(Int),
    completed_at: Option(Int),
  )
}

pub fn encode_execution_state(state: ExecutionState) -> json.Json {
  json.object([
    #("id", json.string(state.id)),
    #("flow_instance", encode_flow_instance(state.flow_instance)),
    #("task_id", json.string(state.task_id)),
    #("status", encode_execution_status(state.status)),
    #("current_node_id", json.nullable(state.current_node_id, json.string)),
    #("step_history", json.array(state.step_history, encode_step_execution)),
    #("loop_counters", json.object(encode_int_dict(state.loop_counters))),
    #("variables", json.object(encode_string_dict(state.variables))),
    #("parallel_active", json.array(state.parallel_active, json.string)),
    #("started_at", json.nullable(state.started_at, json.int)),
    #("completed_at", json.nullable(state.completed_at, json.int)),
  ])
}

pub fn decode_execution_state() -> decode.Decoder(ExecutionState) {
  use id <- decode.field("id", decode.string)
  use flow_instance <- decode.optional_field(
    "flow_instance",
    empty_flow_instance(),
    decode_flow_instance(),
  )
  use task_id <- decode.optional_field("task_id", "", decode.string)
  use status <- decode.field("status", decode_execution_status())
  use current_node_id <- decode.optional_field(
    "current_node_id",
    None,
    decode.optional(decode.string),
  )
  use step_history <- decode.optional_field(
    "step_history",
    [],
    decode.list(decode_step_execution()),
  )
  use loop_counters <- decode.optional_field(
    "loop_counters",
    dict.new(),
    decode.dict(decode.string, decode.int),
  )
  use variables <- decode.optional_field(
    "variables",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  use parallel_active <- decode.optional_field(
    "parallel_active",
    [],
    decode.list(decode.string),
  )
  use started_at <- decode.optional_field(
    "started_at",
    None,
    decode.optional(decode.int),
  )
  use completed_at <- decode.optional_field(
    "completed_at",
    None,
    decode.optional(decode.int),
  )
  decode.success(ExecutionState(
    id:,
    flow_instance:,
    task_id:,
    status:,
    current_node_id:,
    step_history:,
    loop_counters:,
    variables:,
    parallel_active:,
    started_at:,
    completed_at:,
  ))
}

pub fn execution_state_decoder() -> decode.Decoder(ExecutionState) {
  decode_execution_state()
}

pub type SessionLog {
  SessionLog(
    id: String,
    step_execution_id: String,
    task_id: String,
    event_type: String,
    payload: String,
    sequence: Int,
    created_at: Int,
  )
}

pub fn encode_session_log(log: SessionLog) -> json.Json {
  json.object([
    #("id", json.string(log.id)),
    #("step_execution_id", json.string(log.step_execution_id)),
    #("task_id", json.string(log.task_id)),
    #("event_type", json.string(log.event_type)),
    #("payload", json.string(log.payload)),
    #("sequence", json.int(log.sequence)),
    #("created_at", json.int(log.created_at)),
  ])
}

pub fn decode_session_log() -> decode.Decoder(SessionLog) {
  use id <- decode.field("id", decode.string)
  use step_execution_id <- decode.optional_field(
    "step_execution_id",
    "",
    decode.string,
  )
  use task_id <- decode.optional_field("task_id", "", decode.string)
  use event_type <- decode.field("event_type", decode.string)
  use payload <- decode.optional_field("payload", "", decode.string)
  use sequence <- decode.optional_field("sequence", 0, decode.int)
  use created_at <- decode.optional_field("created_at", 0, decode.int)
  decode.success(SessionLog(
    id:,
    step_execution_id:,
    task_id:,
    event_type:,
    payload:,
    sequence:,
    created_at:,
  ))
}

pub fn session_log_decoder() -> decode.Decoder(SessionLog) {
  decode_session_log()
}

// ─── Engine action ──────────────────────────────────────────────────────────

/// The engine action returned by `advance`. Mirrors Crystalline's
/// `flow/executor.Action`.
pub type Action {
  RunStep(node: FlowNode, prompt: String)
  AwaitInput(node: FlowNode)
  RunParallel(children: List(FlowNode))
  FlowComplete
  FlowReject
  ExecutionError(message: String)
}

pub fn encode_action(action: Action) -> json.Json {
  case action {
    RunStep(node:, prompt:) ->
      json.object([
        #("kind", json.string("run_step")),
        #("node", encode_flow_node(node)),
        #("prompt", json.string(prompt)),
      ])
    AwaitInput(node:) ->
      json.object([
        #("kind", json.string("await_input")),
        #("node", encode_flow_node(node)),
      ])
    RunParallel(children:) ->
      json.object([
        #("kind", json.string("run_parallel")),
        #("children", json.array(children, encode_flow_node)),
      ])
    FlowComplete -> json.object([#("kind", json.string("flow_complete"))])
    FlowReject -> json.object([#("kind", json.string("flow_reject"))])
    ExecutionError(message:) ->
      json.object([
        #("kind", json.string("execution_error")),
        #("message", json.string(message)),
      ])
  }
}

pub fn decode_action() -> decode.Decoder(Action) {
  use kind <- decode.then(
    decode.one_of(decode.field("kind", decode.string, decode.success), [
      decode.field("type", decode.string, decode.success),
    ]),
  )
  case kind {
    "run_step" -> {
      use node <- decode.field("node", decode_flow_node())
      use prompt <- decode.optional_field("prompt", "", decode.string)
      decode.success(RunStep(node:, prompt:))
    }
    "await_input" -> {
      use node <- decode.field("node", decode_flow_node())
      decode.success(AwaitInput(node:))
    }
    "run_parallel" -> {
      use children <- decode.optional_field(
        "children",
        [],
        decode.list(decode_flow_node()),
      )
      decode.success(RunParallel(children:))
    }
    "flow_complete" -> decode.success(FlowComplete)
    "flow_reject" -> decode.success(FlowReject)
    "error" | "execution_error" -> {
      use message <- decode.field("message", decode.string)
      decode.success(ExecutionError(message:))
    }
    _ -> decode.failure(ExecutionError("unknown action: " <> kind), "Action")
  }
}

pub fn action_decoder() -> decode.Decoder(Action) {
  decode_action()
}

// ─── Health ─────────────────────────────────────────────────────────────────

pub type HealthStatus {
  HealthStatus(status: String, version: Option(String))
}

pub fn encode_health_status(health: HealthStatus) -> json.Json {
  json.object([
    #("status", json.string(health.status)),
    #("version", json.nullable(health.version, json.string)),
  ])
}

pub fn decode_health_status() -> decode.Decoder(HealthStatus) {
  use status <- decode.field("status", decode.string)
  use version <- decode.optional_field(
    "version",
    None,
    decode.optional(decode.string),
  )
  decode.success(HealthStatus(status:, version:))
}

pub fn health_status_decoder() -> decode.Decoder(HealthStatus) {
  decode_health_status()
}

// ─── Request bodies ─────────────────────────────────────────────────────────

pub type TaskCreate {
  TaskCreate(
    title: String,
    description: Option(String),
    level: TaskLevel,
    priority: Priority,
    tags: List(String),
    parent_id: Option(String),
  )
}

pub fn new_task_create(
  title: String,
  level: TaskLevel,
  priority: Priority,
) -> TaskCreate {
  TaskCreate(
    title: title,
    description: None,
    level: level,
    priority: priority,
    tags: [],
    parent_id: None,
  )
}

pub fn encode_task_create(body: TaskCreate) -> json.Json {
  json.object([
    #("title", json.string(body.title)),
    #("description", json.nullable(body.description, json.string)),
    #("level", encode_task_level(body.level)),
    #("priority", encode_priority(body.priority)),
    #("tags", json.array(body.tags, json.string)),
    #("parent_id", json.nullable(body.parent_id, json.string)),
  ])
}

pub type TaskPatch {
  TaskPatch(
    title: Option(String),
    description: Option(String),
    level: Option(TaskLevel),
    priority: Option(Priority),
    status: Option(TaskStatus),
    parent_id: Option(String),
  )
}

pub fn new_task_patch() -> TaskPatch {
  TaskPatch(
    title: None,
    description: None,
    level: None,
    priority: None,
    status: None,
    parent_id: None,
  )
}

pub fn encode_task_patch(patch: TaskPatch) -> json.Json {
  let entries = []
  let entries = case patch.title {
    Some(title) -> [#("title", json.string(title)), ..entries]
    None -> entries
  }
  let entries = case patch.description {
    Some(description) -> [#("description", json.string(description)), ..entries]
    None -> entries
  }
  let entries = case patch.level {
    Some(level) -> [#("level", encode_task_level(level)), ..entries]
    None -> entries
  }
  let entries = case patch.priority {
    Some(priority) -> [#("priority", encode_priority(priority)), ..entries]
    None -> entries
  }
  let entries = case patch.status {
    Some(status) -> [#("status", encode_task_status(status)), ..entries]
    None -> entries
  }
  let entries = case patch.parent_id {
    Some(parent_id) -> [#("parent_id", json.string(parent_id)), ..entries]
    None -> entries
  }
  json.object(entries)
}

pub type TaskFilters {
  TaskFilters(
    level: Option(TaskLevel),
    status: Option(TaskStatus),
    parent_id: Option(String),
    limit: Option(Int),
    offset: Option(Int),
    ready: Bool,
  )
}

pub fn new_task_filters() -> TaskFilters {
  TaskFilters(
    level: None,
    status: None,
    parent_id: None,
    limit: None,
    offset: None,
    ready: False,
  )
}

pub fn task_filters_to_query(filters: TaskFilters) -> List(#(String, String)) {
  let params = []
  let params = case filters.level {
    Some(level) -> [#("level", task_level_to_string(level)), ..params]
    None -> params
  }
  let params = case filters.status {
    Some(status) -> [#("status", task_status_to_string(status)), ..params]
    None -> params
  }
  let params = case filters.parent_id {
    Some(parent_id) -> [#("parent_id", parent_id), ..params]
    None -> params
  }
  let params = case filters.limit {
    Some(limit) -> [#("limit", int.to_string(limit)), ..params]
    None -> params
  }
  let params = case filters.offset {
    Some(offset) -> [#("offset", int.to_string(offset)), ..params]
    None -> params
  }
  params
}

/// Body for `POST /api/v1/tasks/:id/sections` — the type, text and optional
/// code reference of the new section; the engine assigns `id`, `task_id` and
/// `order`. `code_ref` is omitted (not sent as null) when absent.
pub type SectionCreate {
  SectionCreate(
    section_type: SectionType,
    content: String,
    code_ref: Option(CodeRef),
  )
}

pub fn encode_section_create(body: SectionCreate) -> json.Json {
  let entries = [
    #("section_type", encode_section_type(body.section_type)),
    #("content", json.string(body.content)),
  ]
  json.object(case body.code_ref {
    None -> entries
    Some(code_ref) -> [#("code_ref", encode_code_ref(code_ref)), ..entries]
  })
}

/// Body for `PATCH /api/v1/sections/:id` clearing a section's code reference:
/// `{"code_ref": null}` is the engine's way of detaching it.
pub fn encode_code_ref_clear() -> json.Json {
  json.object([#("code_ref", json.null())])
}

pub type StartFlowRequest {
  StartFlowRequest(template_id: String)
}

pub fn encode_start_flow_request(body: StartFlowRequest) -> json.Json {
  json.object([#("template_id", json.string(body.template_id))])
}

pub type CompleteStepRequest {
  CompleteStepRequest(output: String)
}

pub fn encode_complete_step_request(body: CompleteStepRequest) -> json.Json {
  json.object([#("output", json.string(body.output))])
}

pub type ProvideInputRequest {
  ProvideInputRequest(input: String)
}

pub fn encode_provide_input_request(body: ProvideInputRequest) -> json.Json {
  json.object([#("input", json.string(body.input))])
}

pub type RejectFlowRequest {
  RejectFlowRequest(reason: String)
}

pub fn encode_reject_flow_request(body: RejectFlowRequest) -> json.Json {
  json.object([#("reason", json.string(body.reason))])
}

pub type AppendLogRequest {
  AppendLogRequest(event_type: String, payload: String)
}

/// Body for `POST /api/v1/tasks/:id/dependencies`.
pub type DependencyRequest {
  DependencyRequest(depends_on: String)
}

pub fn encode_dependency_request(body: DependencyRequest) -> json.Json {
  json.object([#("depends_on", json.string(body.depends_on))])
}

/// Generic `{"message": "..."}` response used by the dependency endpoints.
pub type Message {
  Message(message: String)
}

pub fn encode_message(body: Message) -> json.Json {
  json.object([#("message", json.string(body.message))])
}

pub fn decode_message() -> decode.Decoder(Message) {
  use message <- decode.field("message", decode.string)
  decode.success(Message(message:))
}

pub fn message_decoder() -> decode.Decoder(Message) {
  decode_message()
}

pub fn encode_append_log_request(body: AppendLogRequest) -> json.Json {
  json.object([
    #("event_type", json.string(body.event_type)),
    #("payload", json.string(body.payload)),
  ])
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Build a decoder that rejects unknown values with a decode `Error`.
fn strict_enum(
  parse: fn(String) -> Result(a, String),
  fallback: a,
  label: String,
) -> decode.Decoder(a) {
  use value <- decode.then(decode.string)
  case parse(value) {
    Ok(parsed) -> decode.success(parsed)
    Error(message) -> decode.failure(fallback, label <> ": " <> message)
  }
}

/// Decode a JSON number into a `Float`, accepting both integers and floats.
fn decode_float() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

fn encode_node_dict(nodes: Dict(String, FlowNode)) -> json.Json {
  nodes
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, encode_flow_node(pair.1)) })
  |> json.object
}

fn encode_int_dict(values: Dict(String, Int)) -> List(#(String, json.Json)) {
  values
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, json.int(pair.1)) })
}

fn encode_string_dict(
  values: Dict(String, String),
) -> List(#(String, json.Json)) {
  values
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
}

fn empty_flow_instance() -> FlowInstance {
  FlowInstance(
    id: "",
    template_id: "",
    task_id: "",
    nodes: dict.new(),
    transitions: [],
    initial_node_id: "",
    on_done_template_id: None,
    on_reject_template_id: None,
  )
}

// ─── JSON helpers ───────────────────────────────────────────────────────────

pub fn decode_json(
  json_string: String,
  decoder: decode.Decoder(a),
) -> Result(a, json.DecodeError) {
  json.parse(json_string, decoder)
}

pub fn encode_json(value: json.Json) -> String {
  json.to_string(value)
}
