//// Tests for pure command-line parsing.

import facet/cli/args
import facet/cli/types
import facet/models
import gleam/option.{None, Some}
import gleam/string

pub fn empty_args_is_a_usage_error_test() {
  let assert Error(message) = args.parse([])
  assert message == "missing command (run with `facet --help`)"
}

pub fn health_parses_test() {
  let assert Ok(invocation) = args.parse(["health"])
  assert invocation.command == types.Health
  assert invocation.url == None
  assert invocation.token == None
  assert invocation.json == False
}

pub fn help_flag_parses_test() {
  let assert Ok(invocation) = args.parse(["--help"])
  assert invocation.command == types.Help
  let assert Ok(invocation) = args.parse(["-h"])
  assert invocation.command == types.Help
  let assert Ok(invocation) = args.parse(["help"])
  assert invocation.command == types.Help
}

pub fn global_options_parse_test() {
  let assert Ok(invocation) =
    args.parse([
      "--url",
      "http://example.com",
      "--token",
      "sekrit",
      "--json",
      "health",
    ])
  assert invocation.url == Some("http://example.com")
  assert invocation.token == Some("sekrit")
  assert invocation.json == True
  assert invocation.command == types.Health
}

pub fn global_options_support_equals_syntax_test() {
  let assert Ok(invocation) = args.parse(["--url=http://example.com", "health"])
  assert invocation.url == Some("http://example.com")
  let assert Ok(invocation) = args.parse(["--token=x", "health"])
  assert invocation.token == Some("x")
}

pub fn unknown_flag_before_command_is_an_error_test() {
  let assert Error(message) = args.parse(["--bogus", "health"])
  assert message == "unknown flag before command: --bogus"
}

pub fn unknown_command_is_an_error_test() {
  let assert Error(message) = args.parse(["frobnicate"])
  assert message == "unknown command: frobnicate"
}

// ─── task ───────────────────────────────────────────────────────────────────

pub fn task_add_parses_minimal_test() {
  let assert Ok(invocation) = args.parse(["task", "add", "Wire the client"])
  let assert types.TaskAdd(args) = invocation.command
  assert args.title == "Wire the client"
  assert args.description == None
  assert args.level == None
  assert args.priority == None
  assert args.tags == []
  assert args.parent_id == None
}

pub fn task_add_parses_flags_test() {
  let assert Ok(invocation) =
    args.parse([
      "task",
      "add",
      "Wire the client",
      "--level",
      "ticket",
      "--priority",
      "high",
      "--description",
      "Talk to Crystalline",
      "--tag",
      "facet",
      "--tag",
      "http",
      "--parent",
      "epic-1",
    ])
  let assert types.TaskAdd(args) = invocation.command
  assert args.level == Some(models.Ticket)
  assert args.priority == Some(models.High)
  assert args.description == Some("Talk to Crystalline")
  assert args.tags == ["facet", "http"]
  assert args.parent_id == Some("epic-1")
}

pub fn task_add_rejects_invalid_level_test() {
  let assert Error(message) =
    args.parse([
      "task",
      "add",
      "x",
      "--level",
      "saga",
    ])
  assert message == "invalid level: saga (expected epic, ticket or task)"
}

pub fn task_add_rejects_invalid_priority_test() {
  let assert Error(message) =
    args.parse([
      "task",
      "add",
      "x",
      "--priority",
      "urgent",
    ])
  assert message
    == "invalid priority: urgent (expected low, medium, high or critical)"
}

pub fn task_add_requires_title_test() {
  let assert Error(message) = args.parse(["task", "add"])
  assert message == "task add expects a title argument"
  let assert Error(_) = args.parse(["task", "add", "one", "two"])
}

pub fn task_list_parses_ready_and_filters_test() {
  let assert Ok(invocation) =
    args.parse([
      "task",
      "list",
      "--ready",
      "--level",
      "epic",
      "--status",
      "blocked",
      "--parent",
      "p1",
      "--limit",
      "10",
      "--offset",
      "2",
    ])
  let assert types.TaskList(args) = invocation.command
  assert args.ready
  assert args.level == Some(models.Epic)
  assert args.status == Some(models.Blocked)
  assert args.parent_id == Some("p1")
  assert args.limit == Some(10)
  assert args.offset == Some(2)
}

pub fn task_list_rejects_bad_limit_test() {
  let assert Error(message) = args.parse(["task", "list", "--limit", "ten"])
  assert message == "invalid value for --limit: ten"
}

pub fn task_show_parses_test() {
  let assert Ok(invocation) = args.parse(["task", "show", "task-1"])
  let assert types.TaskShow(id) = invocation.command
  assert id == "task-1"
}

pub fn task_update_requires_a_flag_test() {
  let assert Error(message) = args.parse(["task", "update", "task-1"])
  assert message
    == "task update requires at least one flag (--title, --description, --level, --priority, --status, --parent)"
}

pub fn task_update_parses_test() {
  let assert Ok(invocation) =
    args.parse([
      "task",
      "update",
      "task-1",
      "--title",
      "New title",
      "--status",
      "in_progress",
    ])
  let assert types.TaskUpdate(id, args) = invocation.command
  assert id == "task-1"
  assert args.title == Some("New title")
  assert args.status == Some(models.InProgress)
  assert args.description == None
}

pub fn task_delete_parses_cascade_test() {
  let assert Ok(invocation) =
    args.parse(["task", "delete", "task-1", "--cascade"])
  let assert types.TaskDelete(id, cascade) = invocation.command
  assert id == "task-1"
  assert cascade
  let assert Ok(invocation) = args.parse(["task", "delete", "task-1"])
  let assert types.TaskDelete(_, cascade) = invocation.command
  assert cascade == False
}

pub fn task_depend_and_undepend_parse_test() {
  let assert Ok(invocation) = args.parse(["task", "depend", "task-2", "task-1"])
  let assert types.TaskDepend(task_id, depends_on) = invocation.command
  assert task_id == "task-2"
  assert depends_on == "task-1"

  let assert Ok(invocation) =
    args.parse(["task", "undepend", "task-2", "task-1"])
  let assert types.TaskUndepend(task_id, depends_on) = invocation.command
  assert task_id == "task-2"
  assert depends_on == "task-1"
}

pub fn task_blockers_parses_test() {
  let assert Ok(invocation) = args.parse(["task", "blockers", "task-3"])
  let assert types.TaskBlockers(id) = invocation.command
  assert id == "task-3"
}

// ─── flow ───────────────────────────────────────────────────────────────────

pub fn flow_templates_parse_test() {
  let assert Ok(invocation) = args.parse(["flow", "templates"])
  assert invocation.command == types.FlowTemplates
  let assert Ok(invocation) =
    args.parse(["flow", "templates", "show", "linear"])
  let assert types.FlowTemplateShow(id) = invocation.command
  assert id == "linear"
  let assert Ok(invocation) = args.parse(["flow", "template", "linear"])
  let assert types.FlowTemplateShow(id) = invocation.command
  assert id == "linear"
}

pub fn flow_start_parses_test() {
  let assert Ok(invocation) = args.parse(["flow", "start", "task-1", "linear"])
  let assert types.FlowStart(task_id, template_id) = invocation.command
  assert task_id == "task-1"
  assert template_id == "linear"
}

pub fn flow_status_advance_parse_test() {
  let assert Ok(invocation) = args.parse(["flow", "status", "flow-1"])
  let assert types.FlowStatus(instance_id) = invocation.command
  assert instance_id == "flow-1"
  let assert Ok(invocation) = args.parse(["flow", "advance", "flow-1"])
  let assert types.FlowAdvance(instance_id) = invocation.command
  assert instance_id == "flow-1"
}

pub fn flow_complete_step_parses_test() {
  let assert Ok(invocation) =
    args.parse([
      "flow",
      "complete-step",
      "flow-1",
      "node-2",
      "--output",
      "done it",
    ])
  let assert types.FlowCompleteStep(instance_id, step_id, output) =
    invocation.command
  assert instance_id == "flow-1"
  assert step_id == "node-2"
  assert output == "done it"
}

pub fn flow_complete_step_requires_output_test() {
  let assert Error(message) =
    args.parse([
      "flow",
      "complete-step",
      "flow-1",
      "node-2",
    ])
  assert message == "flow complete-step expects --output <text>"
}

pub fn flow_input_joins_remaining_words_test() {
  let assert Ok(invocation) =
    args.parse([
      "flow",
      "input",
      "flow-1",
      "please",
      "review",
      "the",
      "PR",
    ])
  let assert types.FlowInput(instance_id, input) = invocation.command
  assert instance_id == "flow-1"
  assert input == "please review the PR"
}

pub fn flow_reject_parses_reason_test() {
  let assert Ok(invocation) = args.parse(["flow", "reject", "flow-1"])
  let assert types.FlowReject(instance_id, reason) = invocation.command
  assert instance_id == "flow-1"
  assert reason == None
  let assert Ok(invocation) =
    args.parse([
      "flow",
      "reject",
      "flow-1",
      "--reason",
      "out of scope",
    ])
  let assert types.FlowReject(_, Some(reason)) = invocation.command
  assert reason == "out of scope"
}

// ─── exec ───────────────────────────────────────────────────────────────────

pub fn exec_history_show_active_parse_test() {
  let assert Ok(invocation) = args.parse(["exec", "history", "task-1"])
  let assert types.ExecHistory(task_id) = invocation.command
  assert task_id == "task-1"
  let assert Ok(invocation) = args.parse(["exec", "show", "step-9"])
  let assert types.ExecShow(id) = invocation.command
  assert id == "step-9"
  let assert Ok(invocation) = args.parse(["exec", "active"])
  assert invocation.command == types.ExecActive
}

pub fn exec_logs_parses_paging_test() {
  let assert Ok(invocation) =
    args.parse([
      "exec",
      "logs",
      "step-1",
      "--limit",
      "25",
      "--before",
      "40",
    ])
  let assert types.ExecLogs(id, args) = invocation.command
  assert id == "step-1"
  assert args.limit == Some(25)
  assert args.before == Some(40)
}

pub fn double_dash_ends_flag_parsing_test() {
  let assert Ok(invocation) = args.parse(["task", "add", "--", "--weird-title"])
  let assert types.TaskAdd(args) = invocation.command
  assert args.title == "--weird-title"
}

pub fn unknown_flag_after_command_is_an_error_test() {
  let assert Error(message) = args.parse(["task", "list", "--nope"])
  assert message == "unknown flag: --nope"
}

// ─── task sections ──────────────────────────────────────────────────────────

pub fn task_sections_parses_one_id_test() {
  let assert Ok(invocation) = args.parse(["task", "sections", "task-1"])
  assert invocation.command == types.TaskSections("task-1")
}

pub fn task_sections_requires_an_id_test() {
  let assert Error(message) = args.parse(["task", "sections"])
  assert message == "task sections expects a task id"
}

pub fn task_section_add_parses_type_and_content_test() {
  let assert Ok(invocation) =
    args.parse([
      "task",
      "section",
      "add",
      "task-1",
      "--type",
      "testing_criterion",
      "--content",
      "gleam test stays green",
    ])
  let assert types.TaskSectionAdd(id, add) = invocation.command
  assert id == "task-1"
  assert add.section_type == models.TestingCriterion
  assert add.content == "gleam test stays green"
}

pub fn task_section_add_requires_a_type_test() {
  let assert Error(message) =
    args.parse(["task", "section", "add", "task-1", "--content", "Ship it"])
  assert message == "task section add requires --type <section-type>"
}

pub fn task_section_add_requires_content_test() {
  let assert Error(message) =
    args.parse(["task", "section", "add", "task-1", "--type", "goal"])
  assert message == "task section add requires --content <text>"
}

pub fn task_section_add_rejects_unknown_type_test() {
  let assert Error(message) =
    args.parse([
      "task",
      "section",
      "add",
      "task-1",
      "--type",
      "summary",
      "--content",
      "Ship it",
    ])
  assert string.contains(message, "invalid section type: summary")
}

pub fn unknown_task_section_subcommand_is_an_error_test() {
  let assert Error(message) = args.parse(["task", "section", "remove", "s1"])
  assert message == "unknown task section subcommand: remove"
}
