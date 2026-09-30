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

// ─── init / project scope ───────────────────────────────────────────────────

pub fn init_parses_slug_and_optional_name_test() {
  let assert Ok(invocation) = args.parse(["init", "acme"])
  let assert types.Init(init) = invocation.command
  assert init.slug == "acme"
  assert init.name == None

  let assert Ok(invocation) = args.parse(["init", "acme", "--name", "Acme Inc"])
  let assert types.Init(init) = invocation.command
  assert init.name == Some("Acme Inc")
}

pub fn init_requires_exactly_one_slug_test() {
  let assert Error(message) = args.parse(["init"])
  assert message == "init expects a project slug"
  let assert Error(message) = args.parse(["init", "a", "b"])
  assert message == "init takes exactly one slug argument"
}

pub fn project_global_parses_before_the_command_test() {
  let assert Ok(invocation) = args.parse(["--project", "acme", "health"])
  assert invocation.project == Some("acme")
  assert invocation.command == types.Health

  let assert Ok(invocation) = args.parse(["--project=acme", "health"])
  assert invocation.project == Some("acme")

  let assert Ok(invocation) = args.parse(["health"])
  assert invocation.project == None
}

// ─── path / stop ────────────────────────────────────────────────────────────

pub fn path_and_stop_parse_one_id_test() {
  let assert Ok(invocation) = args.parse(["path", "task-2"])
  let assert types.Path(task_id) = invocation.command
  assert task_id == "task-2"

  let assert Ok(invocation) = args.parse(["stop", "flow-1"])
  let assert types.Stop(instance_id) = invocation.command
  assert instance_id == "flow-1"
}

pub fn path_and_stop_require_an_id_test() {
  let assert Error(message) = args.parse(["path"])
  assert message == "path expects an id"
  let assert Error(message) = args.parse(["stop"])
  assert message == "stop expects an id"
}

// ─── task ref / unref ───────────────────────────────────────────────────────

pub fn task_ref_parses_code_reference_flags_test() {
  let assert Ok(invocation) =
    args.parse([
      "task",
      "ref",
      "task-1",
      "src/main.gleam",
      "--line-start",
      "10",
      "--line-end",
      "20",
      "--name",
      "main",
      "--description",
      "entry point",
    ])
  let assert types.TaskRef(task_id, ref) = invocation.command
  assert task_id == "task-1"
  assert ref.code_path == "src/main.gleam"
  assert ref.line_start == Some(10)
  assert ref.line_end == Some(20)
  assert ref.name == Some("main")
  assert ref.description == Some("entry point")
  // Defaults: the section is `context` and its content is the code path.
  assert ref.section_type == models.Context
  assert ref.content == "src/main.gleam"
}

pub fn task_ref_honours_type_and_content_test() {
  let assert Ok(invocation) =
    args.parse([
      "task",
      "ref",
      "task-1",
      "src/main.gleam",
      "--type",
      "failure_test",
      "--content",
      "regression guard",
    ])
  let assert types.TaskRef(_, ref) = invocation.command
  assert ref.section_type == models.FailureTest
  assert ref.content == "regression guard"
}

pub fn task_ref_requires_task_and_path_test() {
  let assert Error(message) = args.parse(["task", "ref"])
  assert message == "task ref expects <task-id> <path>"
  let assert Error(message) = args.parse(["task", "ref", "task-1"])
  assert message == "task ref expects <task-id> <path>"
  let assert Error(message) = args.parse(["task", "ref", "t", "p", "extra"])
  assert message == "task ref takes exactly two positional arguments"
}

pub fn task_ref_rejects_a_bad_line_number_test() {
  let assert Error(message) =
    args.parse([
      "task",
      "ref",
      "task-1",
      "src/main.gleam",
      "--line-start",
      "ten",
    ])
  assert message == "invalid value for --line-start: ten"
}

pub fn task_unref_parses_task_and_section_test() {
  let assert Ok(invocation) = args.parse(["task", "unref", "task-1", "sec-9"])
  let assert types.TaskUnref(task_id, section_id) = invocation.command
  assert task_id == "task-1"
  assert section_id == "sec-9"

  let assert Error(message) = args.parse(["task", "unref", "task-1"])
  assert message == "task unref expects <task-id> <section-id>"
}

// ─── artifact ───────────────────────────────────────────────────────────────

pub fn artifact_subcommands_parse_test() {
  let assert Ok(invocation) = args.parse(["artifact", "task-1", "list"])
  assert invocation.command == types.ArtifactList("task-1")

  let assert Ok(invocation) =
    args.parse(["artifact", "task-1", "get", "plan.json"])
  let assert types.ArtifactGet(task_id, logical_name) = invocation.command
  assert task_id == "task-1"
  assert logical_name == "plan.json"

  let assert Ok(invocation) =
    args.parse([
      "artifact",
      "task-1",
      "put",
      "plan.json",
      "--content",
      "{\"a\":1}",
    ])
  let assert types.ArtifactPut(task_id, logical_name, content) =
    invocation.command
  assert task_id == "task-1"
  assert logical_name == "plan.json"
  assert content == types.InlineContent("{\"a\":1}")

  let assert Ok(invocation) =
    args.parse(["artifact", "task-1", "delete", "plan.json"])
  let assert types.ArtifactDelete(task_id, logical_name) = invocation.command
  assert task_id == "task-1"
  assert logical_name == "plan.json"
}

pub fn artifact_put_dash_selects_stdin_test() {
  let assert Ok(invocation) =
    args.parse(["artifact", "task-1", "put", "plan.json", "--content", "-"])
  let assert types.ArtifactPut(_, _, content) = invocation.command
  assert content == types.StdinContent
}

pub fn artifact_put_requires_content_test() {
  let assert Error(message) =
    args.parse(["artifact", "task-1", "put", "plan.json"])
  assert message == "artifact put requires --content <json|->"
}

pub fn artifact_errors_test() {
  let assert Error(message) = args.parse(["artifact"])
  assert message == "artifact: missing subcommand (get, put, list, delete)"

  let assert Error(message) = args.parse(["artifact", "task-1", "frobnicate"])
  assert message == "unknown artifact subcommand: frobnicate"

  let assert Error(message) = args.parse(["artifact", "task-1", "get"])
  assert message == "artifact get expects <task-id> get <logical-name>"

  let assert Error(message) =
    args.parse(["artifact", "task-1", "list", "extra"])
  assert message == "artifact list takes no logical name"
}
