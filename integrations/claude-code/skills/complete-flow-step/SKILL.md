---
name: complete-flow-step
description: Report the result of a running Crystalline flow step back to the engine through the facet CLI. Use after doing the work a flow's run_step action asked for.
status: active
---

# Report a step result

## When to use

You advanced a flow and got a `run_step` action (its node `id` and `prompt`). Do the
work the prompt asks for, then report the outcome so the flow can continue. Reporting
without doing the step is a lie to the engine — only call this once the work exists.

## Command

```bash
facet --json flow complete-step <instance-id> <step-id> --output "passed: 18 tests, no failures"
```

`<step-id>` is the `node.id` from the `run_step` action. `--output` must be non-empty:
it is stored as the step's result and feeds the next node's prompt.

## Interpreting the output

- stdout is one JSON object: `instance_id`, `step_id`, and `state` — the flow's full
  execution state (`status`, `current_node_id`, `step_history`, `variables`,
  `loop_counters`, `started_at`, `completed_at`).
- exit 0 means the engine recorded the result. The flow has not moved on by itself:
  call `facet --json flow advance <instance-id>` to get the next action, and repeat
  until the action's `kind` is `flow_complete`.
- exit 1: `facet: flow complete-step expects --output <text>` when the output was
  empty, or the engine's error body on stderr (wrong `instance-id` or a `step-id` that
  is not the running step). The state is unchanged, so re-read it with
  `facet --json flow status <instance-id>` before retrying.
