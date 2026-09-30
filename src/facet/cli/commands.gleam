//// Command dispatch: every parsed command becomes exactly one call into the
//// typed client and produces a structured `Output` for the renderer. No
//// formatting happens here, so tests can assert on the structured values.
////
//// The single exception is `init`, which also persists the resolved project as
//// the client default (`facet/config.save_project`) — that is the command's
//// whole purpose.

import facet/cli/types.{type Command, type Output}
import facet/client
import facet/config.{type Config}
import facet/ffi
import facet/models
import gleam/int
import gleam/json
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
    types.Init(args) -> init_project(config, args)
    types.Path(task_id) ->
      client.get_task_path(config, task_id)
      |> as_output(fn(path) { types.TaskPathShown(task_id, path) })
    types.Stop(instance_id) ->
      client.cancel_flow(config, instance_id)
      |> as_output(fn(state) { types.FlowCancelled(instance_id, state) })
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
    types.TaskSections(id) ->
      client.list_sections(config, id)
      |> as_output(fn(sections) { types.SectionsShown(id, sections) })
    types.TaskSectionAdd(id, args) -> add_section(config, id, args)
    types.TaskRef(task_id, args) -> add_code_ref(config, task_id, args)
    types.TaskUnref(_task_id, section_id) ->
      client.clear_section_code_ref(config, section_id)
      |> as_output(fn(section) { types.CodeRefCleared(section_id, section) })
    types.ArtifactGet(task_id, logical_name) ->
      client.get_artifact(config, task_id, logical_name)
      |> as_output(types.ArtifactShown)
    types.ArtifactPut(task_id, logical_name, content) ->
      put_artifact(config, task_id, logical_name, content)
    types.ArtifactList(task_id) ->
      client.list_artifacts(config, task_id)
      |> as_output(fn(artifacts) { types.ArtifactsListed(task_id, artifacts) })
    types.ArtifactDelete(task_id, logical_name) ->
      client.delete_artifact(config, task_id, logical_name)
      |> result.map(fn(_) { types.ArtifactDeleted(task_id, logical_name) })
      |> lift
    types.FlowTemplates ->
      client.list_templates(config)
      |> as_output(types.TemplatesListed)
    types.FlowTemplateShow(id) ->
      client.get_template(config, id)
      |> as_output(types.TemplateShown)
    types.FlowStart(task_id, template_id) ->
      client.start_flow(config, task_id, template_id)
      |> as_output(types.FlowStarted)
    types.FlowStatus(instance_id) ->
      client.get_flow_state(config, instance_id)
      |> as_output(types.FlowStatusShown)
    types.FlowAdvance(instance_id) ->
      client.advance_flow(config, instance_id)
      |> as_output(types.FlowAdvanced)
    types.FlowCompleteStep(instance_id, step_id, output) ->
      client.complete_step(config, instance_id, output)
      |> as_output(fn(step) { types.StepCompleted(step_id, step) })
    types.FlowInput(instance_id, input) ->
      client.provide_input(config, instance_id, input)
      |> as_output(types.InputProvided)
    types.FlowReject(instance_id, reason) ->
      client.reject_flow(config, instance_id, default_reason(reason))
      |> as_output(types.FlowRejected)
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

fn add_section(
  config: Config,
  id: String,
  args: types.TaskSectionAddArgs,
) -> Result(Output, types.CliError) {
  let body =
    models.SectionCreate(
      section_type: args.section_type,
      content: args.content,
      code_ref: None,
    )
  client.create_section(config, id, body)
  |> as_output(types.SectionCreated)
}

/// `task ref` creates a section whose `code_ref` points at the file: a code
/// reference is a section field, never a standalone entity.
fn add_code_ref(
  config: Config,
  task_id: String,
  args: types.TaskRefArgs,
) -> Result(Output, types.CliError) {
  let code_ref =
    models.CodeRef(
      path: args.code_path,
      line_start: args.line_start,
      line_end: args.line_end,
      name: args.name,
      description: args.description,
    )
  let body =
    models.SectionCreate(
      section_type: args.section_type,
      content: args.content,
      code_ref: Some(code_ref),
    )
  client.create_section(config, task_id, body)
  |> as_output(types.CodeRefAdded)
}

// ─── Projects ───────────────────────────────────────────────────────────────

/// `init`: resolve the project by slug, create it when absent, then persist it
/// as the client default. A lost race (someone else created the slug between
/// our lookup and our POST, i.e. a 409) re-reads the project instead of
/// failing.
fn init_project(
  config: Config,
  args: types.InitArgs,
) -> Result(Output, types.CliError) {
  use project <- result.try(resolve_or_create_project(config, args))
  use _ <- result.try(
    config.save_project(project.slug)
    |> result.map_error(types.RequestError),
  )
  Ok(types.ProjectInitialized(project, config.config_file_path()))
}

fn resolve_or_create_project(
  config: Config,
  args: types.InitArgs,
) -> Result(models.Project, types.CliError) {
  case client.get_project(config, args.slug) {
    Ok(project) -> Ok(project)
    Error(config.HttpError(404, _)) ->
      client.create_project(
        config,
        args.slug,
        option.unwrap(args.name, args.slug),
      )
      |> resolve_create_race(config, args.slug)
    Error(error) -> Error(types.RequestError(error))
  }
}

fn resolve_create_race(
  result: Result(models.Project, config.ClientError),
  config: Config,
  slug: String,
) -> Result(models.Project, types.CliError) {
  case result {
    Ok(project) -> Ok(project)
    // 409: the slug appeared between the lookup and the create.
    Error(config.HttpError(409, _)) ->
      client.get_project(config, slug)
      |> as_project
    Error(error) -> Error(types.RequestError(error))
  }
}

fn as_project(
  result: Result(models.Project, config.ClientError),
) -> Result(models.Project, types.CliError) {
  case result {
    Ok(project) -> Ok(project)
    Error(error) -> Error(types.RequestError(error))
  }
}

// ─── Artifacts ──────────────────────────────────────────────────────────────

fn put_artifact(
  config: Config,
  task_id: String,
  logical_name: String,
  source: types.ContentSource,
) -> Result(Output, types.CliError) {
  use raw <- result.try(content_text(source))
  use content <- result.try(parse_content(raw))
  client.put_artifact(config, task_id, logical_name, content)
  |> as_output(types.ArtifactStored)
}

fn content_text(source: types.ContentSource) -> Result(String, types.CliError) {
  case source {
    types.InlineContent(raw) -> Ok(raw)
    types.StdinContent -> Ok(ffi.read_stdin())
  }
}

fn parse_content(raw: String) -> Result(json.Json, types.CliError) {
  case json.parse(raw, models.json_value_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) ->
      Error(types.UsageError("artifact put --content is not valid JSON"))
  }
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
