---
name: read-execution-logs
description: Read a Crystalline execution's session log (paged, newest first) through the facet CLI. Use when the user asks what a run did, why it failed, or wants the transcript of a step.
status: active
---

# Read execution logs

## When to use

A flow step ran and you need its transcript: what the agent emitted, which events
landed, where it stopped. First find the execution id, then page through its log.

## Commands

Find executions for a task, or the ones still running:

```bash
facet --json exec history <task-id>
```

```bash
facet --json exec active
```

Then read the log of one execution:

```bash
facet --json exec logs <exec-id> --limit 50
```

## Interpreting the output

- `exec history` and `exec active` print JSON arrays of step executions (`id`,
  `flow_instance_id`, `node_id`, `task_id`, `status`, `model`, token counts, `cost`,
  `duration_ms`, `prompt`, `output`). Take `id` as the `<exec-id>` above;
  `exec active` additionally shows which runs are still `running` or
  `awaiting_input`.
- `exec logs` prints one object: `logs`, an array of `{id, step_execution_id,
  task_id, event_type, payload, sequence, created_at}` ordered newest first, and
  `paging`, `{has_more, continue_before}`.
- When `has_more` is `true`, the page filled up: continue older entries by adding
  `--before <sequence>` with `continue_before` as the value.
- exit 0 for an empty log too — `logs: []` means the execution produced no events, not
  that the request failed. exit 1 with `facet: <message>` on stderr (unknown
  `<exec-id>` answers 404) means nothing can be said about the log; say so instead of
  reporting an empty transcript.
