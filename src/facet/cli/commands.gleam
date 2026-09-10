//// Command dispatch: every parsed command becomes exactly one call into the
//// typed client and produces a structured `Output` for the renderer. No
//// formatting happens here, so tests can assert on the structured values.

import facet/cli/types.{type Command, type Output}
import facet/client
import facet/config.{type Config}
import facet/models
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Execute one command against the server configured by `config`.
pub fn run(config: Config, command: Command) -> Result(Output, types.CliError) {
  case command {
    types.Health ->
      client.health(config)
      |> as_output(types.HealthOutput)
    types.Help -> Error(types.UsageError("help is handled before dispatch"))
    types.TaskAdd(args) -> add_task(config, args)
    types.TaskList(args) -> list_tasks(config, args)
    types.TaskShow(id) ->
      client.get_task(config, id)
      |> as_output(types.TaskShown)
    types.TaskUpdate(id, args) -> update_task(config, id, args)
    types.TaskDelete(id, cascade) ->
      client.delete_task(config, id, cascade)
      |> result.map(fn(_) { types.TaskDeleted(id, cascade) })
      |> lift
    types.TaskDepend(task_id, depends_on) ->
      client.add_dependency(config, task_id, depends_on)
      |> result.map(fn(_) { types.DependencyAdded(task_id, depends_on) })
      |> lift
    types.TaskUndepend(task_id, depends_on) ->
      client.remove_dependency(config, task_id, depends_on)
      |> result.map(fn(_) { types.DependencyRemoved(task_id, depends_on) })
      |> lift
    types.TaskBlockers(id) ->
      client.get_blockers(config, id)
      |> as_output(fn(blockers) { types.BlockersShown(id, blockers) })
    types.FlowTemplates ->
      client.list_templates(config)
      |> as_output(types.TemplatesListed)
    types.FlowTemplateShow(id) ->
      client.get_template(config, id)
      |> as_output(types.TemplateShown)
    types.FlowStart(task_id, template_id) ->
      client.start_flow(config, task_id, template_id)
      |> as_output(fn(instance) { types.FlowStarted(instance, task_id) })
    types.FlowStatus(instance_id) ->
      client.get_flow_state(config, instance_id)
      |> as_output(types.FlowStatusShown)
    types.FlowAdvance(instance_id) ->
      client.advance_flow(config, instance_id)
      |> as_output(fn(action) { types.FlowAdvanced(instance_id, action) })
    types.FlowCompleteStep(instance_id, step_id, output) ->
      client.complete_step(config, instance_id, step_id, output)
      |> as_output(fn(state) { types.StepCompleted(step_id, state) })
    types.FlowInput(instance_id, input) ->
      client.provide_input(config, instance_id, input)
      |> as_output(fn(state) { types.InputProvided(instance_id, state) })
    types.FlowReject(instance_id, reason) ->
      client.reject_flow(config, instance_id, default_reason(reason))
      |> as_output(fn(state) { types.FlowRejected(instance_id, state) })
    types.ExecHistory(task_id) ->
      client.execution_history(config, task_id)
      |> as_output(fn(steps) { types.ExecHistoryShown(task_id, steps) })
    types.ExecShow(id) ->
      client.get_execution(config, id)
      |> as_output(types.ExecShown)
    types.ExecActive ->
      client.active_executions(config)
      |> as_output(types.ExecActiveShown)
    types.ExecLogs(id, args) -> exec_logs(config, id, args)
  }
}

// ─── Task helpers ───────────────────────────────────────────────────────────

fn add_task(
  config: Config,
  args: types.TaskAddArgs,
) -> Result(Output, types.CliError) {
  let body =
    models.TaskCreate(
      title: args.title,
      description: args.description,
      level: option.unwrap(args.level, models.Ticket),
      priority: option.unwrap(args.priority, models.Medium),
      tags: args.tags,
      parent_id: args.parent_id,
    )
  client.create_task(config, body)
  |> as_output(types.TaskCreated)
}

fn list_tasks(
  config: Config,
  args: types.TaskListArgs,
) -> Result(Output, types.CliError) {
  let filters =
    models.TaskFilters(
      level: args.level,
      status: args.status,
      parent_id: args.parent_id,
      limit: args.limit,
      offset: args.offset,
      ready: args.ready,
    )
  client.list_tasks(config, filters)
  |> as_output(types.TaskListOutput)
}

fn update_task(
  config: Config,
  id: String,
  args: types.TaskUpdateArgs,
) -> Result(Output, types.CliError) {
  let patch =
    models.TaskPatch(
      title: args.title,
      description: args.description,
      level: args.level,
      priority: args.priority,
      status: args.status,
      parent_id: args.parent_id,
    )
  client.update_task(config, id, patch)
  |> as_output(types.TaskUpdated)
}

// ─── Execution helpers ──────────────────────────────────────────────────────

fn exec_logs(
  config: Config,
  id: String,
  args: types.ExecLogsArgs,
) -> Result(Output, types.CliError) {
  client.get_logs(config, id, args.limit, args.before)
  |> result.map(fn(logs) { types.LogsShown(logs, log_paging(logs, args)) })
  |> lift
}

/// A page is "full" when it returned as many entries as requested; continue
/// from `--before <oldest sequence>` to see older entries.
fn log_paging(
  logs: List(models.SessionLog),
  args: types.ExecLogsArgs,
) -> types.LogPaging {
  let page_size = option.unwrap(args.limit, 100)
  let has_more = list.length(logs) >= page_size
  let continue_before = oldest_sequence(logs)
  types.LogPaging(has_more:, continue_before:)
}

fn oldest_sequence(logs: List(models.SessionLog)) -> Option(Int) {
  list.fold(logs, None, fn(minimum, log) {
    case minimum {
      None -> Some(log.sequence)
      Some(current) -> Some(int.min(current, log.sequence))
    }
  })
}

// ─── Error plumbing ─────────────────────────────────────────────────────────

/// Map a client result onto an output constructor, wrapping client errors.
fn as_output(
  result: Result(a, config.ClientError),
  constructor: fn(a) -> Output,
) -> Result(Output, types.CliError) {
  case result {
    Ok(value) -> Ok(constructor(value))
    Error(error) -> Error(types.RequestError(error))
  }
}

/// Lift an already-mapped result to the CLI error type.
fn lift(
  result: Result(Output, config.ClientError),
) -> Result(Output, types.CliError) {
  case result {
    Ok(output) -> Ok(output)
    Error(error) -> Error(types.RequestError(error))
  }
}

fn default_reason(reason: Option(String)) -> String {
  option.unwrap(reason, "Rejected via the facet CLI")
}
