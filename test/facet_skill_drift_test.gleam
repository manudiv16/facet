//// The skills in `integrations/claude-code/skills/` are a second copy of the CLI
//// contract: every `facet …` example they show must still parse with the CLI's
//// own argument parser. This suite reads the skill files, extracts the runnable
//// examples (fenced shell blocks and inline `facet …` spans) and fails on drift —
//// a renamed subcommand, a dropped flag, a wrong arity — plus it pins the skill
//// roster and the front matter the plugin ships.

import facet/cli/args
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

@external(erlang, "facet_fs", "read_file")
fn read_file(path: String) -> Result(String, Nil)

@external(erlang, "facet_fs", "list_dir")
fn list_dir(path: String) -> Result(List(String), Nil)

/// Repository-relative root of the plugin's skills, as documented in
/// `integrations/claude-code/README.md`.
const skills_dir = "integrations/claude-code/skills"

/// The operations issue #12 scopes the integration to. A skill added or
/// removed without updating this list fails the roster test.
const expected_skills = [
  "add-task",
  "archive-task",
  "complete-flow-step",
  "edit-section",
  "list-flow-templates",
  "read-blockers",
  "read-execution-logs",
  "read-sections",
  "start-flow",
  "update-task",
]

// ─── Roster and front matter ────────────────────────────────────────────────

pub fn skill_roster_matches_issue_scope_test() {
  assert skill_names() == expected_skills
}

pub fn every_skill_declares_name_description_and_status_test() {
  let failures =
    skill_names()
    |> list.flat_map(fn(skill) {
      let path = skill_path(skill)
      let content = read(path)
      let front = front_matter(content)
      let name = front_field(front, "name")
      let description = front_field(front, "description")
      let status = front_field(front, "status")
      case
        name == Some(skill)
        && description != None
        && list.contains(["active", "pending"], option_unwrap(status, ""))
      {
        True -> []
        False -> [
          path
          <> ": expected name="
          <> skill
          <> ", a description and status active|pending; got name="
          <> option_unwrap(name, "(missing)")
          <> " status="
          <> option_unwrap(status, "(missing)"),
        ]
      }
    })
  assert failures == []
}

pub fn pending_skills_declare_their_blocker_test() {
  let failures =
    skill_names()
    |> list.flat_map(fn(skill) {
      let path = skill_path(skill)
      let content = read(path)
      case front_field(front_matter(content), "status") {
        Some("pending") -> {
          let missing =
            ["PENDING", "crystalline#16"]
            |> list.filter(fn(marker) { !string.contains(content, marker) })
          case missing {
            [] -> []
            _ -> [
              path
              <> ": pending skill is missing "
              <> string.join(missing, ", "),
            ]
          }
        }
        _ -> []
      }
    })
  assert failures == []
}

// ─── Command drift ──────────────────────────────────────────────────────────

pub fn every_skill_shows_a_runnable_command_test() {
  let empty =
    skill_names()
    |> list.filter(fn(skill) { commands_of(skill) == [] })
  assert empty == []
}

/// Every command example in every skill must parse with `facet/cli/args` — the
/// same parser the live CLI runs. A skill that names a subcommand or flag the
/// CLI no longer implements fails here instead of at runtime.
pub fn skill_commands_parse_with_the_cli_test() {
  let failures =
    skill_names()
    |> list.flat_map(fn(skill) {
      let path = skill_path(skill)
      commands_of(skill)
      |> list.flat_map(fn(command) {
        // The example includes the program name; the parser takes the
        // arguments that follow it, exactly as the VM receives them.
        case shell_split(command) {
          [_program, ..cli_args] ->
            case args.parse(cli_args) {
              Ok(_) -> []
              Error(message) -> [
                path <> ": `" <> command <> "` does not parse: " <> message,
              ]
            }
          [] -> [path <> ": `" <> command <> "` has no arguments"]
        }
      })
    })
  assert failures == []
}

// ─── Skill file parsing ─────────────────────────────────────────────────────

fn skill_names() -> List(String) {
  // `gleam test` runs from the repository root, where the plugin lives.
  let assert Ok(entries) = list_dir(skills_dir)
  list.sort(entries, by: string.compare)
}

fn skill_path(skill: String) -> String {
  skills_dir <> "/" <> skill <> "/SKILL.md"
}

fn read(path: String) -> String {
  let assert Ok(content) = read_file(path)
  content
}

/// The YAML front matter of a skill: the lines between the first `---` and the
/// next one.
fn front_matter(content: String) -> String {
  case string.split(content, "---") {
    [_, front, ..] -> front
    _ -> ""
  }
}

fn front_field(front: String, key: String) -> Option(String) {
  front
  |> string.split("\n")
  |> list.find_map(fn(line) {
    case string.split_once(string.trim(line), ": ") {
      Ok(#(found, value)) if found == key -> Ok(string.trim(value))
      _ -> Error(Nil)
    }
  })
  |> result_option
}

fn result_option(result: Result(a, b)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn option_unwrap(value: Option(String), default: String) -> String {
  case value {
    Some(found) -> found
    None -> default
  }
}

/// Every `facet …` example a skill shows: shell-fenced lines and inline code
/// spans outside fences. Commands quoted in a non-shell fence (such as the
/// `PENDING:` template of a blocked skill) are documentation, not runnable
/// examples, and are skipped.
fn commands_of(skill: String) -> List(String) {
  read(skill_path(skill))
  |> string.split("\n")
  |> segments([])
  |> list.flat_map(commands_in_segment)
}

type Segment {
  Text(String)
  Shell(lines: List(String))
  Other(lines: List(String))
}

/// Split markdown into alternating prose and fenced-code segments.
fn segments(lines: List(String), acc: List(Segment)) -> List(Segment) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case string.starts_with(trimmed, "```") {
        False -> {
          let #(prose, remaining) = take_until_fence(lines, [])
          segments(remaining, [
            Text(string.join(list.reverse(prose), "\n")),
            ..acc
          ])
        }
        True -> {
          let info = string.trim(string.drop_start(trimmed, 3))
          let #(body, remaining) = take_fence_body(rest, [])
          let segment = case
            list.contains(["sh", "bash", "shell", "zsh"], info)
          {
            True -> Shell(list.reverse(body))
            False -> Other(list.reverse(body))
          }
          segments(remaining, [segment, ..acc])
        }
      }
    }
  }
}

/// Consume prose up to (but excluding) the next opening fence.
fn take_until_fence(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(acc, [])
    [line, ..rest] ->
      case string.starts_with(string.trim(line), "```") {
        True -> #(acc, lines)
        False -> take_until_fence(rest, [line, ..acc])
      }
  }
}

/// Consume a fence body up to and including the closing fence line.
fn take_fence_body(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(acc, [])
    [line, ..rest] ->
      case string.trim(line) {
        "```" -> #(acc, rest)
        _ -> take_fence_body(rest, [line, ..acc])
      }
  }
}

fn commands_in_segment(segment: Segment) -> List(String) {
  case segment {
    Shell(lines) ->
      lines
      |> list.map(string.trim)
      |> list.filter(fn(line) { string.starts_with(line, "facet ") })
    Text(text) -> inline_commands(text)
    Other(_) -> []
  }
}

/// `` `facet …` `` spans in prose. The span text after the backtick prefix is
/// the command up to the closing backtick.
fn inline_commands(text: String) -> List(String) {
  text
  |> string.split("`facet ")
  |> list.drop(1)
  |> list.filter_map(fn(tail) {
    case string.split_once(tail, "`") {
      Ok(#(command, _)) if command != "" -> Ok("facet " <> command)
      _ -> Error(Nil)
    }
  })
}

// ─── Shell-style tokenizing ─────────────────────────────────────────────────

/// Split an example the way a shell would: whitespace separates words, and
/// single or double quotes keep spaces inside one argument.
fn shell_split(line: String) -> List(String) {
  split_graphemes(string.to_graphemes(string.trim(line)), [], "", None)
}

fn split_graphemes(
  graphemes: List(String),
  done: List(String),
  current: String,
  quote: Option(String),
) -> List(String) {
  case graphemes, quote {
    [], _ -> finish(done, current)
    [grapheme, ..rest], Some(open) if grapheme == open ->
      split_graphemes(rest, done, current, None)
    [grapheme, ..rest], Some(_) ->
      split_graphemes(rest, done, current <> grapheme, quote)
    [grapheme, ..rest], None ->
      case grapheme {
        "\"" | "'" -> split_graphemes(rest, done, current, Some(grapheme))
        " " | "\t" -> split_graphemes(rest, add_word(done, current), "", None)
        _ -> split_graphemes(rest, done, current <> grapheme, None)
      }
  }
}

fn add_word(done: List(String), current: String) -> List(String) {
  case current {
    "" -> done
    _ -> [current, ..done]
  }
}

fn finish(done: List(String), current: String) -> List(String) {
  list.reverse(add_word(done, current))
}
