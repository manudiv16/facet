---
name: read-blockers
description: List the tasks blocking a Crystalline task through the facet CLI. Use when the user asks why a task is blocked, what it depends on, or what has to finish first.
status: active
---

# Read blockers

## When to use

A task is stuck and the user wants to know what is holding it up — "why is this
blocked?", "what has to land first?". The answer is the task's open dependencies.

## Command

```bash
facet --json task blockers <task-id>
```

## Interpreting the output

- stdout is a JSON **array** of task objects (same shape as `task add` returns), one
  per dependency that is not finished. An empty array `[]` means nothing blocks the
  task and it can be worked on.
- Each entry carries `id`, `short_id`, `title`, `level`, `priority`, `status` — use
  `facet --json task show <id>` on an entry to get its full description.
- exit 0 for both cases: blockers found or none. exit 1 with `facet: <message>` on
  stderr means the request failed (unknown `id` answers 404), and the array tells you
  nothing — do not report "unblocked" on that basis.
- To drop an edge once the blocker is done, the engine removes it with
  `facet --json task undepend <task-id> <depends-on-id>`.
