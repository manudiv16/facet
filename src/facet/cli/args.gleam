//// Pure command-line parsing for the Facet CLI. No I/O, so every branch is
//// unit-testable. Global options (`--url`, `--token`, `--json`) must precede
//// the command; per-command flags follow it.

import facet/cli/types
import facet/models
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Parse a full argument list (program name excluded) into an invocation.
pub fn parse(args: List(String)) -> Result(types.ParsedInvocation, String) {
  case extract_globals(args) {
    Error(message) -> Error(message)
    Ok(globals) ->
      case globals.remaining {
        [] -> Error("missing command (run with `facet --help`)")
        [name, ..rest] -> {
          use command <- result.try(parse_command(name, rest))
          Ok(types.ParsedInvocation(
            url: globals.url,
            token: globals.token,
            json: globals.json,
            command: command,
          ))
        }
      }
  }
}

// ─── Global options ─────────────────────────────────────────────────────────

type Globals {
  Globals(
    url: Option(String),
    token: Option(String),
    json: Bool,
    remaining: List(String),
  )
}

fn extract_globals(args: List(String)) -> Result(Globals, String) {
  case args {
    [] -> Ok(base_globals())
    ["--help", ..] ->
      Ok(Globals(..base_globals(), json: False, remaining: ["help"]))
    ["-h", ..] ->
      Ok(Globals(..base_globals(), json: False, remaining: ["help"]))
    ["help", ..] ->
      Ok(Globals(..base_globals(), json: False, remaining: ["help"]))
    ["--url", url, ..rest] ->
      extract_globals(rest)
      |> result.map(fn(g) { Globals(..g, url: Some(url)) })
    ["--url=" <> url, ..rest] ->
      extract_globals(rest)
      |> result.map(fn(g) { Globals(..g, url: optional_nonempty(url)) })
    ["--token", token, ..rest] ->
      extract_globals(rest)
      |> result.map(fn(g) { Globals(..g, token: Some(token)) })
    ["--token=" <> token, ..rest] ->
      extract_globals(rest)
      |> result.map(fn(g) { Globals(..g, token: optional_nonempty(token)) })
    ["--json", ..rest] ->
      extract_globals(rest)
      |> result.map(fn(g) { Globals(..g, json: True) })
    ["--" <> flag, ..] if flag != "" ->
      Error("unknown flag before command: --" <> first_flag_name(flag))
    _ -> Ok(Globals(url: None, token: None, json: False, remaining: args))
  }
}

fn base_globals() -> Globals {
  Globals(url: None, token: None, json: False, remaining: [])
}

fn optional_nonempty(value: String) -> Option(String) {
  case value {
    "" -> None
    _ -> Some(value)
  }
}

fn first_flag_name(flag: String) -> String {
  case string.split_once(flag, "=") {
    Ok(#(name, _)) -> name
    Error(_) -> flag
  }
}

// ─── Command dispatch ───────────────────────────────────────────────────────

fn parse_command(
  name: String,
  args: List(String),
) -> Result(types.Command, String) {
  case name, args {
    "health", [] -> Ok(types.Health)
    "help", [] -> Ok(types.Help)
    "task", [sub, ..rest] -> parse_task(sub, rest)
    "task", [] -> Error(task_subcommand_help())
    "flow", [sub, ..rest] -> parse_flow(sub, rest)
    "flow", [] -> Error(flow_subcommand_help())
    "exec", [sub, ..rest] -> parse_exec(sub, rest)
    "exec", [] -> Error(exec_subcommand_help())
    _, _ -> Error("unknown command: " <> name)
  }
}

fn task_subcommand_help() -> String {
  "task: missing subcommand (add, list, show, update, delete, depend, undepend, blockers, sections, section)"
}

fn flow_subcommand_help() -> String {
  "flow: missing subcommand (templates, template, start, status, advance, complete-step, input, reject)"
}

fn exec_subcommand_help() -> String {
  "exec: missing subcommand (history, show, active, logs)"
}

// ─── Tokenizer ─────────────────────────────────────────────────────────────-

/// A flat arg list split into positionals, flag values and present boolean
/// flags. Values for `value_flags` are consumed from the next token (or via
/// `--flag=value`); `bool_flags` only mark presence. `--` ends flag parsing.
type Tokens {
  Tokens(
    positionals: List(String),
    values: Dict(String, List(String)),
    present: List(String),
  )
}

type TokenizerState {
  TokenizerState(
    positionals: List(String),
    values: Dict(String, List(String)),
    present: List(String),
  )
}

fn tokenize(
  args: List(String),
  value_flags: List(String),
  bool_flags: List(String),
) -> Result(Tokens, String) {
  let initial = TokenizerState(positionals: [], values: dict.new(), present: [])
  go_tokenize(args, value_flags, bool_flags, initial)
  |> result.map(fn(state) {
    Tokens(
      positionals: list.reverse(state.positionals),
      values: state.values,
      present: state.present,
    )
  })
}

fn go_tokenize(
  args: List(String),
  value_flags: List(String),
  bool_flags: List(String),
  state: TokenizerState,
) -> Result(TokenizerState, String) {
  case args {
    [] -> Ok(state)
    ["--", ..rest] ->
      Ok(TokenizerState(
        positionals: list.append(list.reverse(rest), state.positionals),
        values: state.values,
        present: state.present,
      ))
    [arg, ..rest] ->
      case flag_name_of(arg) {
        None ->
          go_tokenize(
            rest,
            value_flags,
            bool_flags,
            TokenizerState(
              positionals: [arg, ..state.positionals],
              values: state.values,
              present: state.present,
            ),
          )
        Some(name) ->
          case list.contains(value_flags, name) {
            True ->
              case flag_value(arg) {
                Some(value) ->
                  set_value(name, value, rest, value_flags, bool_flags, state)
                None ->
                  case rest {
                    [] -> Error("flag --" <> name <> " requires a value")
                    [value, ..tail] ->
                      set_value(
                        name,
                        value,
                        tail,
                        value_flags,
                        bool_flags,
                        state,
                      )
                  }
              }
            False ->
              case list.contains(bool_flags, name) {
                True ->
                  go_tokenize(
                    rest,
                    value_flags,
                    bool_flags,
                    TokenizerState(
                      positionals: state.positionals,
                      values: state.values,
                      present: [name, ..state.present],
                    ),
                  )
                False -> Error("unknown flag: --" <> name)
              }
          }
      }
  }
}

fn set_value(
  name: String,
  value: String,
  rest: List(String),
  value_flags: List(String),
  bool_flags: List(String),
  state: TokenizerState,
) -> Result(TokenizerState, String) {
  let current = dict.get(state.values, name)
  let updated = case current {
    Ok(existing) -> dict.insert(state.values, name, [value, ..existing])
    Error(_) -> dict.insert(state.values, name, [value])
  }
  go_tokenize(
    rest,
    value_flags,
    bool_flags,
    TokenizerState(
      positionals: state.positionals,
      values: updated,
      present: state.present,
    ),
  )
}

/// `--name=value` -> `Some("name=value")`, `--name` -> `Some("name")`,
/// anything else -> `None`.
fn flag_name_of(arg: String) -> Option(String) {
  case string.starts_with(arg, "--") && string.length(arg) > 2 {
    True -> Some(string.drop_start(arg, 2))
    False -> None
  }
}

fn flag_value(arg: String) -> Option(String) {
  case string.split_once(arg, "=") {
    Ok(#(_, value)) -> Some(value)
    Error(_) -> None
  }
}

// ─── Flag reading helpers ───────────────────────────────────────────────────

fn value_of(tokens: Tokens, name: String) -> Option(String) {
  case dict.get(tokens.values, name) {
    Ok([first, ..]) -> Some(first)
    _ -> None
  }
}

fn values_of(tokens: Tokens, name: String) -> List(String) {
  case dict.get(tokens.values, name) {
    Ok(values) -> list.reverse(values)
    Error(_) -> []
  }
}

fn is_present(tokens: Tokens, name: String) -> Bool {
  list.contains(tokens.present, name)
}

fn parse_int_flag(tokens: Tokens, name: String) -> Result(Option(Int), String) {
  case value_of(tokens, name) {
    None -> Ok(None)
    Some(raw) ->
      case int.parse(raw) {
        Ok(value) if value >= 0 -> Ok(Some(value))
        _ -> Error("invalid value for --" <> name <> ": " <> raw)
      }
  }
}

fn parse_level(tokens: Tokens) -> Result(Option(models.TaskLevel), String) {
  case value_of(tokens, "level") {
    None -> Ok(None)
    Some(raw) ->
      case models.task_level_from_string(raw) {
        Ok(level) -> Ok(Some(level))
        Error(_) ->
          Error("invalid level: " <> raw <> " (expected epic, ticket or task)")
      }
  }
}

fn parse_priority(tokens: Tokens) -> Result(Option(models.Priority), String) {
  case value_of(tokens, "priority") {
    None -> Ok(None)
    Some(raw) ->
      case models.priority_from_string(raw) {
        Ok(priority) -> Ok(Some(priority))
        Error(_) ->
          Error(
            "invalid priority: "
            <> raw
            <> " (expected low, medium, high or critical)",
          )
      }
  }
}

fn parse_status(tokens: Tokens) -> Result(Option(models.TaskStatus), String) {
  case value_of(tokens, "status") {
    None -> Ok(None)
    Some(raw) ->
      case models.task_status_from_string(raw) {
        Ok(status) -> Ok(Some(status))
        Error(_) ->
          Error(
            "invalid status: "
            <> raw
            <> " (expected todo, in_progress, blocked, done, cancelled or archived)",
          )
      }
  }
}

// ─── task ──────────────────────────────────────────────────────────────────

fn parse_task(
  sub: String,
  args: List(String),
) -> Result(types.Command, String) {
  case sub {
    "add" -> parse_task_add(args)
    "list" -> parse_task_list(args)
    "show" -> parse_task_show(args)
    "update" -> parse_task_update(args)
    "delete" -> parse_task_delete(args)
    "depend" -> parse_task_depend(args)
    "undepend" -> parse_task_undepend(args)
    "blockers" -> parse_task_blockers(args)
    "sections" -> parse_task_sections(args)
    "section" -> parse_task_section(args)
    _ -> Error("unknown task subcommand: " <> sub)
  }
}

fn parse_task_add(args: List(String)) -> Result(types.Command, String) {
  let value_flags = ["description", "level", "priority", "parent", "tag"]
  use tokens <- result.try(tokenize(args, value_flags, []))
  case tokens.positionals {
    [title] -> {
      use level <- result.try(parse_level(tokens))
      use priority <- result.try(parse_priority(tokens))
      Ok(
        types.TaskAdd(types.TaskAddArgs(
          title: title,
          description: value_of(tokens, "description"),
          level: level,
          priority: priority,
          tags: values_of(tokens, "tag"),
          parent_id: value_of(tokens, "parent"),
        )),
      )
    }
    [] -> Error("task add expects a title argument")
    _ -> Error("task add takes exactly one title argument")
  }
}

fn parse_task_list(args: List(String)) -> Result(types.Command, String) {
  let value_flags = ["level", "status", "parent", "limit", "offset"]
  use tokens <- result.try(tokenize(args, value_flags, ["ready"]))
  case tokens.positionals {
    [] -> {
      use level <- result.try(parse_level(tokens))
      use status <- result.try(parse_status(tokens))
      use limit <- result.try(parse_int_flag(tokens, "limit"))
      use offset <- result.try(parse_int_flag(tokens, "offset"))
      Ok(
        types.TaskList(types.TaskListArgs(
          level: level,
          status: status,
          parent_id: value_of(tokens, "parent"),
          limit: limit,
          offset: offset,
          ready: is_present(tokens, "ready"),
        )),
      )
    }
    _ -> Error("task list takes no positional arguments")
  }
}

fn parse_task_show(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, [], []))
  case tokens.positionals {
    [id] -> Ok(types.TaskShow(id))
    [] -> Error("task show expects a task id")
    _ -> Error("task show takes exactly one id argument")
  }
}

fn parse_task_update(args: List(String)) -> Result(types.Command, String) {
  let value_flags = [
    "title",
    "description",
    "level",
    "priority",
    "status",
    "parent",
  ]
  use tokens <- result.try(tokenize(args, value_flags, []))
  case tokens.positionals {
    [id] -> {
      use level <- result.try(parse_level(tokens))
      use priority <- result.try(parse_priority(tokens))
      use status <- result.try(parse_status(tokens))
      let update =
        types.TaskUpdateArgs(
          title: value_of(tokens, "title"),
          description: value_of(tokens, "description"),
          level: level,
          priority: priority,
          status: status,
          parent_id: value_of(tokens, "parent"),
        )
      case update {
        types.TaskUpdateArgs(
          title: None,
          description: None,
          level: None,
          priority: None,
          status: None,
          parent_id: None,
        ) ->
          Error(
            "task update requires at least one flag (--title, --description, --level, --priority, --status, --parent)",
          )
        _ -> Ok(types.TaskUpdate(id, update))
      }
    }
    [] -> Error("task update expects a task id")
    _ -> Error("task update takes exactly one id argument")
  }
}

fn parse_task_delete(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, [], ["cascade"]))
  case tokens.positionals {
    [id] -> Ok(types.TaskDelete(id, is_present(tokens, "cascade")))
    [] -> Error("task delete expects a task id")
    _ -> Error("task delete takes exactly one id argument")
  }
}

fn parse_task_depend(args: List(String)) -> Result(types.Command, String) {
  case args {
    [task_id, depends_on] -> Ok(types.TaskDepend(task_id, depends_on))
    [] -> Error("task depend expects <task-id> <depends-on-id>")
    _ -> Error("task depend takes exactly two id arguments")
  }
}

fn parse_task_undepend(args: List(String)) -> Result(types.Command, String) {
  case args {
    [task_id, depends_on] -> Ok(types.TaskUndepend(task_id, depends_on))
    [] -> Error("task undepend expects <task-id> <depends-on-id>")
    _ -> Error("task undepend takes exactly two id arguments")
  }
}

fn parse_task_blockers(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, [], []))
  case tokens.positionals {
    [id] -> Ok(types.TaskBlockers(id))
    [] -> Error("task blockers expects a task id")
    _ -> Error("task blockers takes exactly one id argument")
  }
}

fn parse_task_sections(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, [], []))
  case tokens.positionals {
    [id] -> Ok(types.TaskSections(id))
    [] -> Error("task sections expects a task id")
    _ -> Error("task sections takes exactly one id argument")
  }
}

fn parse_task_section(args: List(String)) -> Result(types.Command, String) {
  case args {
    ["add", ..rest] -> parse_task_section_add(rest)
    [] -> Error("task section: missing subcommand (add)")
    [sub, ..] -> Error("unknown task section subcommand: " <> sub)
  }
}

fn parse_task_section_add(args: List(String)) -> Result(types.Command, String) {
  let value_flags = ["type", "content"]
  use tokens <- result.try(tokenize(args, value_flags, []))
  case tokens.positionals {
    [id] -> {
      use section_type <- result.try(parse_section_type(tokens))
      use content <- result.try(parse_section_content(tokens))
      Ok(types.TaskSectionAdd(
        id,
        types.TaskSectionAddArgs(section_type:, content:),
      ))
    }
    [] -> Error("task section add expects a task id")
    _ -> Error("task section add takes exactly one id argument")
  }
}

fn parse_section_type(tokens: Tokens) -> Result(models.SectionType, String) {
  case value_of(tokens, "type") {
    None -> Error("task section add requires --type <section-type>")
    Some(raw) ->
      case models.section_type_from_string(raw) {
        Ok(section_type) -> Ok(section_type)
        Error(_) ->
          Error(
            "invalid section type: "
            <> raw
            <> " (expected goal, context, current_behavior, desired_behavior, checklist_item, testing_criterion, constraint, anti_pattern or failure_test)",
          )
      }
  }
}

fn parse_section_content(tokens: Tokens) -> Result(String, String) {
  case value_of(tokens, "content") {
    None -> Error("task section add requires --content <text>")
    Some("") -> Error("task section add requires --content <text>")
    Some(content) -> Ok(content)
  }
}

// ─── flow ──────────────────────────────────────────────────────────────────

fn parse_flow(
  sub: String,
  args: List(String),
) -> Result(types.Command, String) {
  case sub {
    "templates" -> parse_flow_templates(args)
    "template" -> parse_flow_templates(args)
    "start" -> {
      case args {
        [task_id, template_id] -> Ok(types.FlowStart(task_id, template_id))
        [] -> Error("flow start expects <task-id> <template-id>")
        _ -> Error("flow start takes exactly two arguments")
      }
    }
    "status" -> parse_one_id("flow status", types.FlowStatus, args)
    "advance" -> parse_one_id("flow advance", types.FlowAdvance, args)
    "complete-step" -> parse_flow_complete_step(args)
    "input" -> parse_flow_input(args)
    "reject" -> parse_flow_reject(args)
    _ -> Error("unknown flow subcommand: " <> sub)
  }
}

fn parse_flow_templates(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, [], []))
  case tokens.positionals {
    [] -> Ok(types.FlowTemplates)
    ["show", id] -> Ok(types.FlowTemplateShow(id))
    ["show"] -> Error("flow templates show expects a template id")
    [id] -> Ok(types.FlowTemplateShow(id))
    _ ->
      Error(
        "flow templates takes no arguments, or `show <id>` for one template",
      )
  }
}

fn parse_flow_complete_step(
  args: List(String),
) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, ["output"], []))
  case tokens.positionals {
    [instance_id, step_id] ->
      case value_of(tokens, "output") {
        Some(output) if output != "" ->
          Ok(types.FlowCompleteStep(instance_id, step_id, output))
        _ -> Error("flow complete-step expects --output <text>")
      }
    [] ->
      Error(
        "flow complete-step expects <instance-id> <step-id> --output <text>",
      )
    _ -> Error("flow complete-step takes exactly two positional arguments")
  }
}

fn parse_flow_input(args: List(String)) -> Result(types.Command, String) {
  case args {
    [instance_id, ..text] -> {
      let input = string.join(text, " ")
      case input {
        "" -> Error("flow input expects <instance-id> <text>")
        _ -> Ok(types.FlowInput(instance_id, input))
      }
    }
    [] -> Error("flow input expects <instance-id> <text>")
  }
}

fn parse_flow_reject(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, ["reason"], []))
  case tokens.positionals {
    [instance_id] ->
      Ok(types.FlowReject(instance_id, value_of(tokens, "reason")))
    [] -> Error("flow reject expects an instance id")
    _ -> Error("flow reject takes exactly one positional argument")
  }
}

fn parse_one_id(
  label: String,
  constructor: fn(String) -> types.Command,
  args: List(String),
) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, [], []))
  case tokens.positionals {
    [id] -> Ok(constructor(id))
    [] -> Error(label <> " expects an instance id")
    _ -> Error(label <> " takes exactly one id argument")
  }
}

// ─── exec ──────────────────────────────────────────────────────────────────

fn parse_exec(
  sub: String,
  args: List(String),
) -> Result(types.Command, String) {
  case sub {
    "history" -> parse_one_id("exec history", types.ExecHistory, args)
    "show" -> parse_one_id("exec show", types.ExecShow, args)
    "active" -> {
      case args {
        [] -> Ok(types.ExecActive)
        _ -> Error("exec active takes no arguments")
      }
    }
    "logs" -> parse_exec_logs(args)
    _ -> Error("unknown exec subcommand: " <> sub)
  }
}

fn parse_exec_logs(args: List(String)) -> Result(types.Command, String) {
  use tokens <- result.try(tokenize(args, ["limit", "before"], []))
  case tokens.positionals {
    [id] -> {
      use limit <- result.try(parse_int_flag(tokens, "limit"))
      use before <- result.try(parse_int_flag(tokens, "before"))
      Ok(types.ExecLogs(id, types.ExecLogsArgs(limit: limit, before: before)))
    }
    [] -> Error("exec logs expects an execution id")
    _ -> Error("exec logs takes exactly one id argument")
  }
}
