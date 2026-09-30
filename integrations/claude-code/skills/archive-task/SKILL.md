---
name: archive-task
description: Archive a Crystalline task (optionally cascading to subtasks) through the facet CLI. Use when the user asks to archive, retire or remove a task they no longer want tracked.
status: active
---

# Archive a task

## When to use

The task should stop being active work. This is the engine's archive operation: the
CLI's `task delete` hits `DELETE /api/v1/tasks/:id`, which archives the task and only
removes subtasks when `--cascade` is passed (the desktop app's archive action calls
the same endpoint).

To merely mark a task's status without archiving, patch it instead with
`facet --json task update <task-id> --status cancelled`.

## Command

```bash
facet --json task delete <task-id>
```

Add `--cascade` only when the task's children must go too:

```bash
facet --json task delete <task-id> --cascade
```

## Interpreting the output

- stdout is one JSON object: `{"deleted": "<task-id>", "cascade": true|false}`. It
  echoes what was requested, so treat it as a receipt, not as engine state.
- exit 0 means the engine archived the task.
- exit 1: the engine's error body on stderr — an unknown `id` answers 404, and the
  task stays exactly as it was. Nothing was archived.
