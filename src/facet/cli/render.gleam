//// Rendering of structured command outputs. Two modes share one `Output`
//// value: human-readable text (default) and JSON (`--json`). Everything here
//// is pure, so renderers are covered by plain unit tests.

import facet/cli/types.{type Output}
import facet/models
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ─── Human-readable rendering ───────────────────────────────────────────────

/// Render an output for display. Never raises on unexpected values.
pub fn render(output: Output) -> String {
  case output {
    types.HealthOutput(health) -> render_health(health)
    types.ProjectInitialized(project, config_path) -> {
      render_lines([
        #("project", project.slug),
        #("id", project.id),
        #("name", project.name),
        #("config", config_path),
      ])
      <> "project initialized; later commands are scoped to it\n"
    }
    types.TaskPathShown(task_id, path) -> render_task_path(task_id, path)
    types.FlowCancelled(instance_id, state) ->
      "flow cancelled: "
      <> instance_id
      <> "\n"
      <> render_lines([
        #("status", models.execution_status_to_string(state.status)),
        #("completed", option_int(state.completed_at)),
      ])
    types.TaskCreated(task) -> "task created:\n" <> render_task(task)
    types.TaskShown(task) -> render_task(task)
    types.TaskUpdated(task) -> "task updated:\n" <> render_task(task)
    types.TaskListOutput(tasks) -> render_task_table(tasks)
    types.TaskDeleted(id, cascade) ->
      case cascade {
        True -> "task deleted (cascade): " <> id
        False -> "task deleted: " <> id
      }
    types.DependencyAdded(task_id, depends_on) ->
      "dependency added: " <> task_id <> " -> " <> depends_on
    types.DependencyRemoved(task_id, depends_on) ->
      "dependency removed: " <> task_id <> " -x-> " <> depends_on
    types.BlockersShown(task_id, blockers) ->
      "blockers of " <> task_id <> ":\n" <> render_task_table(blockers)
    types.SectionsShown(task_id, sections) ->
      "sections of " <> task_id <> ":\n" <> render_section_table(sections)
    types.SectionCreated(section) ->
      "section added:\n" <> render_section(section)
    types.CodeRefAdded(section) ->
      "code reference added (section "
      <> section.id
      <> "):\n"
      <> render_section(section)
    types.CodeRefCleared(section_id, section) ->
      "code reference cleared (section "
      <> section_id
      <> "):\n"
      <> render_section(section)
    types.ArtifactsListed(task_id, artifacts) ->
      "artifacts of " <> task_id <> ":\n" <> render_artifact_table(artifacts)
    types.ArtifactShown(artifact) -> render_artifact(artifact)
    types.ArtifactStored(artifact) ->
      "artifact stored:\n" <> render_artifact(artifact)
    types.ArtifactDeleted(task_id, logical_name) ->
      "artifact deleted: " <> logical_name <> " (" <> task_id <> ")"
    types.TemplatesListed(templates) -> render_template_table(templates)
    types.TemplateShown(template) -> render_template(template)
    types.FlowStarted(instance, task_id) ->
      "flow started:\n"
      <> render_lines([
        #("instance", instance.id),
        #("template", instance.template_id),
        #("task", task_id),
        #("initial node", instance.initial_node_id),
      ])
    types.FlowStatusShown(state) -> render_state(state)
    types.FlowAdvanced(instance_id, action) ->
      render_action(instance_id, action)
    types.StepCompleted(step_id, state) ->
      "step completed: " <> step_id <> "\n" <> render_state(state)
    types.InputProvided(instance_id, state) ->
      "input provided for instance "
      <> instance_id
      <> "\n"
      <> render_state(state)
    types.FlowRejected(instance_id, state) ->
      "flow rejected: " <> instance_id <> "\n" <> render_state(state)
    types.ExecHistoryShown(task_id, steps) ->
      "executions of " <> task_id <> ":\n" <> render_step_table(steps)
    types.ExecShown(step) -> render_step(step)
    types.ExecActiveShown(steps) ->
      "active executions:\n" <> render_step_table(steps)
    types.LogsShown(logs, paging) -> render_logs(logs, paging)
  }
}

fn render_health(health: models.HealthStatus) -> String {
  let version = case health.version {
    Some(v) -> v
    None -> "(unknown)"
  }
  render_lines([
    #("status", health.status),
    #("version", version),
    #("base url", "see FACET_URL / --url"),
  ])
}

/// Aligned key/value block, e.g. `status: ok`.
fn render_lines(entries: List(#(String, String))) -> String {
  let width =
    list.fold(list.map(entries, fn(pair) { string.length(pair.0) }), 0, int.max)
  entries
  |> list.map(fn(pair) {
    let label = pair.0 <> string.repeat(" ", width - string.length(pair.0))
    label <> ": " <> pair.1
  })
  |> string.join("\n")
  |> ensure_trailing_newline
}

// ─── Tasks ─────────────────────────────────────────────────────────────────

pub fn render_task(task: models.Task) -> String {
  let flow = case task.flow_instance_id {
    Some(instance) -> instance
    None -> "(none)"
  }
  render_lines([
    #("id", task.id),
    #("short id", task.short_id),
    #("title", task.title),
    #("description", task.description),
    #("level", models.task_level_to_string(task.level)),
    #("priority", models.priority_to_string(task.priority)),
    #("status", models.task_status_to_string(task.status)),
    #("tags", string.join(task.tags, ", ")),
    #("parent", option_string(task.parent_id)),
    #("flow", flow),
    #("created", int.to_string(task.created_at)),
    #("updated", int.to_string(task.updated_at)),
  ])
}

pub fn render_task_table(tasks: List(models.Task)) -> String {
  case tasks {
    [] -> "no tasks"
    _ -> {
      let rows =
        list.map(tasks, fn(task) {
          [
            task.id,
            task.short_id,
            models.task_level_to_string(task.level),
            models.priority_to_string(task.priority),
            models.task_status_to_string(task.status),
            task.title,
          ]
        })
      let widths = column_widths(rows, [12, 8, 7, 8, 11, 0])
      let header = [
        pad_to("ID", 12),
        pad_to("SHORT", 8),
        pad_to("LEVEL", 7),
        pad_to("PRIORITY", 8),
        pad_to("STATUS", 11),
        "TITLE",
      ]
      let table = [string.join(header, "  "), ..render_table_rows(rows, widths)]
      string.join(table, "\n")
    }
  }
}

/// Pad each cell to its column width; a width of 0 leaves the cell as-is.
fn render_table_rows(
  rows: List(List(String)),
  widths: List(Int),
) -> List(String) {
  list.map(rows, fn(row) { string.join(pad_row(row, widths), "  ") })
}

fn pad_row(row: List(String), widths: List(Int)) -> List(String) {
  case row, widths {
    [cell, ..rest], [width, ..rest_widths] -> {
      let padded = case width > 0 {
        True -> pad_to(cell, width)
        False -> cell
      }
      [padded, ..pad_row(rest, rest_widths)]
    }
    [cell, ..rest], [] -> [cell, ..pad_row(rest, [])]
    [], _ -> []
  }
}

fn column_widths(rows: List(List(String)), fallback: List(Int)) -> List(Int) {
  list.fold(rows, fallback, fn(widths, row) { widen(widths, row) })
}

fn widen(widths: List(Int), row: List(String)) -> List(Int) {
  case widths, row {
    [width, ..rest_widths], [cell, ..rest_cells] -> [
      int.max(width, string.length(cell)),
      ..widen(rest_widths, rest_cells)
    ]
    [], [cell, ..rest_cells] -> [string.length(cell), ..widen([], rest_cells)]
    [width, ..rest_widths], [] -> [width, ..rest_widths]
    [], [] -> []
  }
}

/// Breadcrumb of the path root→task: `id title > id title > …`.
fn render_task_path(task_id: String, path: List(models.Task)) -> String {
  let breadcrumb =
    path
    |> list.map(fn(task) { task.id <> " " <> task.title })
    |> string.join(" > ")
  let breadcrumb = case breadcrumb {
    "" -> "(empty path)"
    _ -> breadcrumb
  }
  "path to " <> task_id <> ":\n" <> breadcrumb <> "\n"
}

// ─── Task sections ──────────────────────────────────────────────────────────

fn render_section_table(sections: List(models.Section)) -> String {
  case sections {
    [] -> "no sections"
    _ -> {
      let rows =
        list.map(sections, fn(section) {
          [
            section.id,
            models.section_type_to_string(section.section_type),
            int.to_string(section.order),
            section.content,
            render_code_ref(section.code_ref),
          ]
        })
      let widths = column_widths(rows, [12, 20, 6, 0, 24])
      let header = [
        pad_to("ID", 12),
        pad_to("TYPE", 20),
        pad_to("ORDER", 6),
        "CONTENT",
        pad_to("CODE REF", 24),
      ]
      let table = [string.join(header, "  "), ..render_table_rows(rows, widths)]
      string.join(table, "\n")
    }
  }
}

fn render_section(section: models.Section) -> String {
  render_lines([
    #("id", section.id),
    #("task", section.task_id),
    #("type", models.section_type_to_string(section.section_type)),
    #("order", int.to_string(section.order)),
    #("content", section.content),
    #("code ref", render_code_ref(section.code_ref)),
  ])
}

/// `path:12-40 (name)` or `(none)`; a code reference is a section field, so
/// this is the only place it shows up.
fn render_code_ref(code_ref: Option(models.CodeRef)) -> String {
  case code_ref {
    None -> "(none)"
    Some(ref) -> {
      let lines = case ref.line_start, ref.line_end {
        Some(start), Some(end) ->
          ":" <> int.to_string(start) <> "-" <> int.to_string(end)
        Some(start), None -> ":" <> int.to_string(start)
        None, Some(end) -> ":0-" <> int.to_string(end)
        None, None -> ""
      }
      let name = case ref.name {
        Some(name) -> " (" <> name <> ")"
        None -> ""
      }
      let description = case ref.description {
        Some(text) -> " — " <> text
        None -> ""
      }
      ref.path <> lines <> name <> description
    }
  }
}

// ─── Artifacts ──────────────────────────────────────────────────────────────

fn render_artifact_table(artifacts: List(models.Artifact)) -> String {
  case artifacts {
    [] -> "no artifacts"
    _ -> {
      let rows =
        list.map(artifacts, fn(artifact) {
          [
            artifact.logical_name,
            int.to_string(artifact.updated_at),
            truncate(json.to_string(artifact.content), 60),
          ]
        })
      let widths = column_widths(rows, [20, 12, 0])
      let header = [
        pad_to("NAME", 20),
        pad_to("UPDATED", 12),
        "CONTENT",
      ]
      let table = [string.join(header, "  "), ..render_table_rows(rows, widths)]
      string.join(table, "\n")
    }
  }
}

fn render_artifact(artifact: models.Artifact) -> String {
  render_lines([
    #("id", artifact.id),
    #("task", artifact.task_id),
    #("name", artifact.logical_name),
    #("updated", int.to_string(artifact.updated_at)),
    #("content", json.to_string(artifact.content)),
  ])
}

/// Keep table rows readable; the full value is always available via `--json`.
fn truncate(value: String, limit: Int) -> String {
  case string.length(value) > limit {
    True -> string.slice(value, 0, limit) <> "…"
    False -> value
  }
}

// ─── Flow templates ─────────────────────────────────────────────────────────

fn render_template_table(templates: List(models.FlowTemplate)) -> String {
  case templates {
    [] -> "no flow templates"
    _ -> {
      let rows =
        list.map(templates, fn(template) {
          [
            template.id,
            template.name,
            int.to_string(dict.size(template.nodes)),
            template.initial_node_id,
            template.description,
          ]
        })
      let widths = column_widths(rows, [12, 12, 6, 12, 0])
      let header = [
        pad_to("ID", 12),
        pad_to("NAME", 12),
        pad_to("NODES", 6),
        pad_to("START", 12),
        "DESCRIPTION",
      ]
      let table = [string.join(header, "  "), ..render_table_rows(rows, widths)]
      string.join(table, "\n")
    }
  }
}

fn render_template(template: models.FlowTemplate) -> String {
  let node_lines =
    template.nodes
    |> dict.to_list
    |> list.sort(by: fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) {
      let node = pair.1
      "  "
      <> node.id
      <> "  "
      <> models.node_type_to_string(node.node_type)
      <> "  "
      <> node.name
    })
  let transition_lines =
    template.transitions
    |> list.map(fn(transition) {
      let condition = case transition.condition {
        Some(c) -> " when " <> c
        None -> ""
      }
      "  " <> transition.from_id <> " -> " <> transition.to_id <> condition
    })
  let nodes = case node_lines {
    [] -> "(none)"
    _ -> string.join(node_lines, "\n") <> "\n"
  }
  let transitions = case transition_lines {
    [] -> "(none)"
    _ -> string.join(transition_lines, "\n") <> "\n"
  }
  render_lines([
    #("id", template.id),
    #("name", template.name),
    #("description", template.description),
    #("initial node", template.initial_node_id),
    #("nodes", int.to_string(dict.size(template.nodes))),
    #("transitions", int.to_string(list.length(template.transitions))),
  ])
  <> "nodes:\n"
  <> nodes
  <> "transitions:\n"
  <> transitions
}

// ─── Execution state / actions ──────────────────────────────────────────────

fn render_state(state: models.ExecutionState) -> String {
  let current = case state.current_node_id {
    Some(node_id) -> node_id <> node_name_hint(state, node_id)
    None -> "(none)"
  }
  let variables = case dict.size(state.variables) {
    0 -> "{}"
    _ -> dict_to_string(state.variables)
  }
  let loops = case dict.size(state.loop_counters) {
    0 -> "{}"
    _ ->
      state.loop_counters
      |> dict.to_list
      |> list.map(fn(pair) { pair.0 <> ": " <> int.to_string(pair.1) })
      |> string.join(", ")
  }
  render_lines([
    #("instance", state.flow_instance.id),
    #("task", state.task_id),
    #("status", models.execution_status_to_string(state.status)),
    #("current node", current),
    #("steps completed", int.to_string(list.length(state.step_history))),
    #("started", option_int(state.started_at)),
    #("completed", option_int(state.completed_at)),
    #("variables", variables),
    #("loop counters", loops),
  ])
}

fn node_name_hint(state: models.ExecutionState, node_id: String) -> String {
  case dict.get(state.flow_instance.nodes, node_id) {
    Ok(node) -> " (" <> node.name <> ")"
    Error(_) -> ""
  }
}

fn dict_to_string(values: Dict(String, String)) -> String {
  let sorted =
    values
    |> dict.to_list
    |> list.sort(by: fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) { pair.0 <> "=" <> pair.1 })
  "{" <> string.join(sorted, ", ") <> "}"
}

fn render_action(instance_id: String, action: models.Action) -> String {
  case action {
    models.RunStep(node:, prompt:) ->
      render_lines([
        #("action", "run_step"),
        #("node", node.id <> " (" <> node.name <> ")"),
        #("goal", node.goal),
        #("prompt", prompt),
      ])
      <> "next: run the step and report its result:\n"
      <> "  facet flow complete-step "
      <> instance_id
      <> " "
      <> node.id
      <> " --output \"<result>\"\n"
    models.AwaitInput(node:) ->
      render_lines([
        #("action", "await_input"),
        #("node", node.id <> " (" <> node.name <> ")"),
        #("goal", node.goal),
      ])
      <> "next: provide the input the flow is waiting for:\n"
      <> "  facet flow input "
      <> instance_id
      <> " \"<text>\"\n"
    models.RunParallel(children:) ->
      render_lines([
        #("action", "run_parallel"),
        #("children", int.to_string(list.length(children))),
      ])
      <> "next: advance again once the parallel steps are done:\n"
      <> "  facet flow advance "
      <> instance_id
      <> "\n"
    models.FlowComplete ->
      render_lines([
        #("action", "flow_complete"),
        #("instance", instance_id),
      ])
      <> "next: the flow finished; check the task status:\n"
      <> "  facet task show <task-id>\n"
    models.FlowReject ->
      render_lines([
        #("action", "flow_reject"),
        #("instance", instance_id),
      ])
      <> "next: the flow was rejected; the task stays blocked:\n"
      <> "  facet flow status "
      <> instance_id
      <> "\n"
    models.ExecutionError(message:) ->
      render_lines([
        #("action", "execution_error"),
        #("instance", instance_id),
        #("message", message),
      ])
      <> "next: reject the flow to stop it:\n"
      <> "  facet flow reject "
      <> instance_id
      <> " --reason \"aborted after error\"\n"
  }
}

// ─── Step executions ────────────────────────────────────────────────────────

pub fn render_step_table(steps: List(models.StepExecution)) -> String {
  case steps {
    [] -> "no executions"
    _ -> {
      let rows =
        list.map(steps, fn(step) {
          [
            step.id,
            step.node_id,
            models.step_status_to_string(step.status),
            option_string(step.model),
            int.to_string(step.input_tokens),
            float.to_string(step.cost),
            int.to_string(step.duration_ms),
          ]
        })
      let widths = column_widths(rows, [12, 8, 11, 18, 10, 9, 11])
      let header = [
        pad_to("ID", 12),
        pad_to("NODE", 8),
        pad_to("STATUS", 11),
        pad_to("MODEL", 18),
        pad_to("TOKENS", 10),
        pad_to("COST", 9),
        pad_to("DURATION", 11),
      ]
      let table = [string.join(header, "  "), ..render_table_rows(rows, widths)]
      string.join(table, "\n")
    }
  }
}

pub fn render_step(step: models.StepExecution) -> String {
  render_lines([
    #("id", step.id),
    #("flow instance", step.flow_instance_id),
    #("execution state", step.execution_state_id),
    #("node", step.node_id),
    #("task", step.task_id),
    #("status", models.step_status_to_string(step.status)),
    #("model", option_string(step.model)),
    #(
      "tokens",
      int.to_string(step.input_tokens)
        <> " in / "
        <> int.to_string(step.output_tokens)
        <> " out",
    ),
    #("cost", float.to_string(step.cost)),
    #("duration", int.to_string(step.duration_ms) <> "ms"),
    #("prompt", option_string(step.prompt)),
    #("output", option_string(step.output)),
    #("transition result", option_string(step.transition_result)),
    #("created", int.to_string(step.created_at)),
    #("completed", option_int(step.completed_at)),
  ])
}

// ─── Session logs ───────────────────────────────────────────────────────────

fn render_logs(
  logs: List(models.SessionLog),
  paging: types.LogPaging,
) -> String {
  case logs {
    [] -> "no logs"
    _ -> {
      let rows =
        list.map(logs, fn(log) {
          [
            int.to_string(log.sequence),
            log.event_type,
            log.payload,
          ]
        })
      let widths = column_widths(rows, [4, 14, 0])
      let header = [
        pad_to("SEQ", 4),
        pad_to("EVENT", 14),
        "PAYLOAD",
      ]
      let table = [string.join(header, "  "), ..render_table_rows(rows, widths)]
      let body = string.join(table, "\n")
      let hint = case paging.has_more, paging.continue_before {
        True, Some(before) ->
          "\n(more logs available; continue with: facet exec logs <id> --before "
          <> int.to_string(before)
          <> ")"
        _, _ -> ""
      }
      body <> hint <> "\n"
    }
  }
}

// ─── JSON rendering (--json) ────────────────────────────────────────────────

/// Render an output as a JSON document for scripting.
pub fn render_json(output: Output) -> String {
  json.to_string(json_of(output))
}

fn json_of(output: Output) -> json.Json {
  case output {
    types.HealthOutput(health) -> models.encode_health_status(health)
    types.ProjectInitialized(project, config_path) ->
      json.object([
        #("project", models.encode_project(project)),
        #("config_path", json.string(config_path)),
      ])
    types.TaskPathShown(task_id, path) ->
      json.object([
        #("task_id", json.string(task_id)),
        #("path", json.array(path, models.encode_task)),
      ])
    types.FlowCancelled(instance_id, state) ->
      json.object([
        #("instance_id", json.string(instance_id)),
        #("state", models.encode_execution_state(state)),
      ])
    types.TaskCreated(task) -> models.encode_task(task)
    types.TaskShown(task) -> models.encode_task(task)
    types.TaskUpdated(task) -> models.encode_task(task)
    types.TaskListOutput(tasks) -> json.array(tasks, models.encode_task)
    types.TaskDeleted(id, cascade) ->
      json.object([
        #("deleted", json.string(id)),
        #("cascade", json.bool(cascade)),
      ])
    types.DependencyAdded(task_id, depends_on) ->
      json.object([
        #("task_id", json.string(task_id)),
        #("depends_on", json.string(depends_on)),
        #("message", json.string("Dependency added")),
      ])
    types.DependencyRemoved(task_id, depends_on) ->
      json.object([
        #("task_id", json.string(task_id)),
        #("depends_on", json.string(depends_on)),
        #("message", json.string("Dependency removed")),
      ])
    types.BlockersShown(_, blockers) -> json.array(blockers, models.encode_task)
    types.SectionsShown(_, sections) ->
      json.array(sections, models.encode_section)
    types.SectionCreated(section) -> models.encode_section(section)
    types.CodeRefAdded(section) -> models.encode_section(section)
    types.CodeRefCleared(section_id, section) ->
      json.object([
        #("section_id", json.string(section_id)),
        #("section", models.encode_section(section)),
      ])
    types.ArtifactsListed(task_id, artifacts) ->
      json.object([
        #("task_id", json.string(task_id)),
        #("artifacts", json.array(artifacts, models.encode_artifact)),
      ])
    types.ArtifactShown(artifact) -> models.encode_artifact(artifact)
    types.ArtifactStored(artifact) -> models.encode_artifact(artifact)
    types.ArtifactDeleted(task_id, logical_name) ->
      json.object([
        #("task_id", json.string(task_id)),
        #("logical_name", json.string(logical_name)),
        #("deleted", json.bool(True)),
      ])
    types.TemplatesListed(templates) ->
      json.array(templates, models.encode_flow_template)
    types.TemplateShown(template) -> models.encode_flow_template(template)
    types.FlowStarted(instance, task_id) ->
      json.object([
        #("instance", models.encode_flow_instance(instance)),
        #("task_id", json.string(task_id)),
      ])
    types.FlowStatusShown(state) -> models.encode_execution_state(state)
    types.FlowAdvanced(instance_id, action) ->
      json.object([
        #("instance_id", json.string(instance_id)),
        #("action", models.encode_action(action)),
      ])
    types.StepCompleted(step_id, state) ->
      json.object([
        #("instance_id", json.string(state.flow_instance.id)),
        #("step_id", json.string(step_id)),
        #("state", models.encode_execution_state(state)),
      ])
    types.InputProvided(instance_id, state) ->
      json.object([
        #("instance_id", json.string(instance_id)),
        #("state", models.encode_execution_state(state)),
      ])
    types.FlowRejected(instance_id, state) ->
      json.object([
        #("instance_id", json.string(instance_id)),
        #("state", models.encode_execution_state(state)),
      ])
    types.ExecHistoryShown(task_id, steps) ->
      json.object([
        #("task_id", json.string(task_id)),
        #("executions", json.array(steps, models.encode_step_execution)),
      ])
    types.ExecShown(step) -> models.encode_step_execution(step)
    types.ExecActiveShown(steps) ->
      json.array(steps, models.encode_step_execution)
    types.LogsShown(logs, paging) ->
      json.object([
        #("logs", json.array(logs, models.encode_session_log)),
        #(
          "paging",
          json.object([
            #("has_more", json.bool(paging.has_more)),
            #(
              "continue_before",
              json.nullable(paging.continue_before, json.int),
            ),
          ]),
        ),
      ])
  }
}

// ─── Help text ──────────────────────────────────────────────────────────────

pub fn usage() -> String {
  "facet — CLI for the Crystalline AI workflow engine

usage:
  facet [--url <base-url>] [--token <token>] [--project <id|slug>] [--json] <command> [args...]

global options:
  --url <base-url>     Override FACET_URL (default http://localhost:4920)
  --token <token>      Override FACET_TOKEN
  --project <id|slug>  Project scope for this invocation; sent as
                       X-Crystalline-Project. Overrides FACET_PROJECT and the
                       project saved by `facet init`.
  --json               Machine-readable JSON output
  -h, --help           Show this help

commands:
  health                                  Show server health
  init <slug> [--name <name>]             Resolve or create a project and make
                                          it the default scope for later commands
  path <task-id>                          Show the task's path root -> task
  stop <instance-id>                      Cancel a running flow execution
  task add <title> [flags]                Create a task
  task list [flags]                       List tasks (--ready: only unblocked)
  task show <id>                          Show one task
  task update <id> [flags]                Update a task
  task delete <id> [--cascade]            Archive a task (delete when cascading)
  task depend <id> <depends-on>           <id> blocks until <depends-on> is done
  task undepend <id> <depends-on>         Remove a dependency
  task blockers <id>                      Show tasks blocking <id>
  task sections <id>                      List a task's structured sections
  task section add <id> --type <t> --content <text>   Append a section
  task ref <id> <path> [flags]            Attach a code reference: creates a
                                          section with code_ref {path,line_start,
                                          line_end,name,description}
  task unref <id> <section-id>            Clear a section's code reference
  artifact <task-id> list                 List a task's artifacts
  artifact <task-id> get <name>           Show one artifact (arbitrary JSON)
  artifact <task-id> put <name> --content <json|->   Store an artifact (- reads stdin)
  artifact <task-id> delete <name>        Delete an artifact
  flow templates                          List flow templates
  flow templates show <id>                Show one flow template
  flow start <task-id> <template-id>      Start a flow for a task
  flow status <instance-id>               Show the flow's execution state
  flow advance <instance-id>              Advance the flow, printing its action
  flow complete-step <i> <step> --output <text>   Complete a running step
  flow input <instance-id> <text>         Provide input for a human-input node
  flow reject <instance-id> [--reason <t>] Reject the flow
  exec history <task-id>                  Step execution history of a task
  exec show <exec-id>                     Show one step execution
  exec active                             List active executions
  exec logs <exec-id> [--limit N] [--before SEQ]   Session logs (paged)

project scope (id or slug):
  --project <id|slug>  >  FACET_PROJECT env  >  config file (facet init)  >  absent
  When unset the engine uses its `default` project; an unknown scope is a 404
  telling you to run `facet init` or pass --project.

task add flags:    --description <text>  --level epic|ticket|task  --priority low|medium|high|critical  --tag <t> (repeatable)  --parent <id>
task list flags:   --level <l>  --status <s>  --parent <id>  --limit <n>  --offset <n>  --ready
task update flags: --title <t>  --description <d>  --level <l>  --priority <p>  --status <s>  --parent <id>
section add flags: --type goal|context|current_behavior|desired_behavior|checklist_item|testing_criterion|constraint|anti_pattern|failure_test  --content <text>
task ref flags:    --line-start <n>  --line-end <n>  --name <x>  --description <y>  --type <t> (default context)  --content <text> (default <path>)
                   a code reference is a section field, not a separate entity: ref is `task section add` with code_ref, unref is a PATCH of /sections/:id that sets code_ref to null

exit status:
  0  success (including --help)
  1  any error (usage, network, HTTP, decode)
"
}

// ─── Small helpers ──────────────────────────────────────────────────────────

fn option_string(value: Option(String)) -> String {
  case value {
    Some(v) -> v
    None -> "(none)"
  }
}

fn option_int(value: Option(Int)) -> String {
  case value {
    Some(v) -> int.to_string(v)
    None -> "(none)"
  }
}

fn ensure_trailing_newline(value: String) -> String {
  case string.ends_with(value, "\n") {
    True -> value
    False -> value <> "\n"
  }
}

fn pad_to(value: String, width: Int) -> String {
  let length = string.length(value)
  case length >= width {
    True -> value
    False -> value <> string.repeat(" ", width - length)
  }
}
