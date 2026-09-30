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

`<step-id>` is the `node.id` from the `run_step` action — the node the engine is
currently running (it completes that node itself and echoes the id in the output).
`--output` must be non-empty: it is stored as the step's result and feeds the next
node's prompt.

## Interpreting the output

- stdout is one JSON object: `step_id`, `execution` (the state after the step — `id`,
  `instance_id`, `task_id`, `status`, `current_node_id`, `started_at`,
  `completed_at`) and `action` (the engine's next action, tagged `type`).
- exit 0 means the engine recorded the result and answered with the next action. Call
  `facet --json flow advance <instance-id>` to act on it, and repeat until the action's
  `type` is `flow_complete`.
- exit 1: `facet: flow complete-step expects --output <text>` when the output was
  empty, or the engine's error body on stderr (an unknown `instance-id`, or an
  execution that is not `running`). The execution is unchanged, so re-read the task
  with `facet --json task show <task-id>` before retrying.
