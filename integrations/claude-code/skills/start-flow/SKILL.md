---
name: start-flow
description: Start a Crystalline flow instance for a task from a template through the facet CLI. Use when the user asks to run a workflow, kick off a template or begin an automated process on a task.
status: active
---

# Start a flow

## When to use

A task needs a workflow run against it — implement-and-review, triage, anything the
engine has seeded. You need both the `task-id` and the `template-id`; get the template
from `list-flow-templates` if it is unknown.

## Command

```bash
facet --json flow start <task-id> <template-id>
```

## Interpreting the output

- stdout is one JSON object: `instance` (the flow instance — `id`, `template_id`,
  `task_id`, `nodes`, `transitions`, `initial_node_id`) and `task_id`. Save
  `instance.id`; every later flow command takes it.
- exit 0 means the engine created the instance and bound it to the task.
- exit 1: `facet: <message>` on stderr — an unknown task or template answers 404, and
  no instance was created.
- Starting a flow does not execute anything by itself. Advance it to get the first
  action: `facet --json flow advance <instance-id>` returns
  `{"instance_id": …, "action": {"kind": "run_step"|"await_input"|"run_parallel"|
  "flow_complete"|"flow_reject"|"execution_error", …}}`. A `run_step` action carries
  the node's `id` and `prompt` — that `id` is the `<step-id>` for
  `complete-flow-step`.
