//// Public types of the Facet CLI: parsed invocations, structured command
//// outputs and errors. This module holds only types (plus tiny helpers) so
//// that parsing, dispatch and rendering can be tested in isolation.

import facet/config
import facet/models
import gleam/option.{type Option}

// ─── Parsed invocation ─────────────────────────────────────────────────────

/// A fully parsed command line. `url`/`token`/`json` are the global options
/// that may appear before the command; they override the environment.
pub type ParsedInvocation {
  ParsedInvocation(
    url: Option(String),
    token: Option(String),
    json: Bool,
    command: Command,
  )
}

// ─── Commands ──────────────────────────────────────────────────────────────

/// Every command the CLI understands. Argument-carrying commands wrap small
/// records so flag values are easy to build and assert on.
pub type Command {
  Health
  /// `--help` / `-h` / `help`
  Help
  TaskAdd(TaskAddArgs)
  TaskList(TaskListArgs)
  TaskShow(id: String)
  TaskUpdate(id: String, args: TaskUpdateArgs)
  TaskDelete(id: String, cascade: Bool)
  TaskDepend(task_id: String, depends_on: String)
  TaskUndepend(task_id: String, depends_on: String)
  TaskBlockers(id: String)
  FlowTemplates
  FlowTemplateShow(id: String)
  FlowStart(task_id: String, template_id: String)
  FlowStatus(instance_id: String)
  FlowAdvance(instance_id: String)
  FlowCompleteStep(instance_id: String, step_id: String, output: String)
  FlowInput(instance_id: String, input: String)
  FlowReject(instance_id: String, reason: Option(String))
  ExecHistory(task_id: String)
  ExecShow(id: String)
  ExecActive
  ExecLogs(id: String, args: ExecLogsArgs)
}

pub type TaskAddArgs {
  TaskAddArgs(
    title: String,
    description: Option(String),
    level: Option(models.TaskLevel),
    priority: Option(models.Priority),
    tags: List(String),
    parent_id: Option(String),
  )
}

pub type TaskListArgs {
  TaskListArgs(
    level: Option(models.TaskLevel),
    status: Option(models.TaskStatus),
    parent_id: Option(String),
    limit: Option(Int),
    offset: Option(Int),
    ready: Bool,
  )
}

pub type TaskUpdateArgs {
  TaskUpdateArgs(
    title: Option(String),
    description: Option(String),
    level: Option(models.TaskLevel),
    priority: Option(models.Priority),
    status: Option(models.TaskStatus),
    parent_id: Option(String),
  )
}

pub type ExecLogsArgs {
  ExecLogsArgs(limit: Option(Int), before: Option(Int))
}

// ─── Structured outputs ────────────────────────────────────────────────────

/// The structured result of running a command. Rendering turns this into
/// either human-readable text or JSON; tests assert on it directly.
pub type Output {
  HealthOutput(health: models.HealthStatus)
  TaskCreated(task: models.Task)
  TaskListOutput(tasks: List(models.Task))
  TaskShown(task: models.Task)
  TaskUpdated(task: models.Task)
  TaskDeleted(id: String, cascade: Bool)
  DependencyAdded(task_id: String, depends_on: String)
  DependencyRemoved(task_id: String, depends_on: String)
  BlockersShown(task_id: String, blockers: List(models.Task))
  TemplatesListed(templates: List(models.FlowTemplate))
  TemplateShown(template: models.FlowTemplate)
  FlowStarted(instance: models.FlowInstance, task_id: String)
  FlowStatusShown(state: models.ExecutionState)
  FlowAdvanced(instance_id: String, action: models.Action)
  StepCompleted(step_id: String, state: models.ExecutionState)
  InputProvided(instance_id: String, state: models.ExecutionState)
  FlowRejected(instance_id: String, state: models.ExecutionState)
  ExecHistoryShown(task_id: String, steps: List(models.StepExecution))
  ExecShown(step: models.StepExecution)
  ExecActiveShown(steps: List(models.StepExecution))
  LogsShown(logs: List(models.SessionLog), paging: LogPaging)
}

/// Paging state for `exec logs`: when a page fills up the user can continue
/// with `--before <oldest sequence>`.
pub type LogPaging {
  LogPaging(has_more: Bool, continue_before: Option(Int))
}

// ─── Errors ────────────────────────────────────────────────────────────────

/// Every CLI failure. Usage errors come from bad command lines; request
/// errors are transport/server/decode failures from the client.
pub type CliError {
  UsageError(message: String)
  RequestError(error: config.ClientError)
}

/// Human-readable rendering of a CLI error.
pub fn error_to_string(error: CliError) -> String {
  case error {
    UsageError(message) -> message
    RequestError(client_error) -> config.error_to_string(client_error)
  }
}
