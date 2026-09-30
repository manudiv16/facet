---
name: add-task
description: Create a task, ticket or epic in Crystalline through the facet CLI. Use when the user asks to add, create, file or track a new piece of work.
status: active
---

# Add a task

## When to use

The user wants a new work item recorded in Crystalline — "add a ticket", "file a bug",
"create an epic for the migration". Use `update-task` for something that already
exists and `archive-task` to retire it.

## Command

```bash
facet --json task add "Add rate limiting to the ingest API" --level ticket --priority high --tag api
```

Flags: `--description <text>` for the body, `--level epic|ticket|task` (default
`ticket`), `--priority low|medium|high|critical` (default `medium`), `--tag <t>` once
per tag, `--parent <id>` to nest the new task under an existing epic.

## Interpreting the output

- stdout is exactly one JSON object: `id` (the handle every later command needs),
  `short_id`, `title`, `description`, `level`, `priority`, `status` (`todo` for a new
  task), `tags`, `parent_id`, `archived`, `created_at`, `updated_at`.
- exit 0 means the row was written; read it back with
  `facet --json task show <task-id>` when the id has to be confirmed.
- exit 1: stderr carries `facet: <message>` — an invalid flag value, an unreachable
  `FACET_URL`, or the engine's error body. Nothing was created, so fix the input and
  retry rather than assuming success.
