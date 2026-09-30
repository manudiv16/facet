---
name: update-task
description: Change fields of an existing Crystalline task (title, description, level, priority, status, parent) through the facet CLI. Use when the user asks to edit, retitle, reprioritise or move a task.
status: active
---

# Update a task

## When to use

A task already exists and one of its fields has to change: retitle it, move it to
`in_progress`, raise the priority, reparent it under another epic. New work belongs in
`add-task`; retiring a task belongs in `archive-task`.

## Command

```bash
facet --json task update <task-id> --title "Investigate flaky deploy" --status in_progress --priority high
```

Flags (at least one is required): `--title <t>`, `--description <d>`, `--level
epic|ticket|task`, `--priority low|medium|high|critical`, `--status
todo|in_progress|blocked|done|cancelled|archived`, `--parent <id>`. Only the fields you
pass are patched; everything else is left untouched by the engine.

## Interpreting the output

- stdout is one JSON object — the task as it looks **after** the patch. Confirm the
  changed field (`status`, `priority`, …) rather than trusting the call.
- exit 0 means the engine accepted the patch.
- exit 1: `facet: task update requires at least one flag (…)` when no flag was given,
  `facet: invalid status: …` for a bad value, or the engine's error body (an unknown
  `id` answers 404) on stderr. In every case the task is unchanged.
