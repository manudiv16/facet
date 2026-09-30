---
name: list-flow-templates
description: List the flow templates a Crystalline instance ships with, or show one template's graph, through the facet CLI. Use before starting a flow or when the user asks what workflows are available.
status: active
---

# List flow templates

## When to use

Before starting a flow you need its `template-id`, or the user asks which workflows the
engine offers ("what can we run on this task?", "is there an implement-and-review
flow?").

## Command

```bash
facet --json flow templates
```

One template in detail — its nodes, transitions and start node:

```bash
facet --json flow templates show <template-id>
```

## Interpreting the output

- `flow templates` prints a JSON **array of summaries**: `id` (use this with
  `facet --json flow start <task-id> <template-id>`), `slug`, `name`, `description`,
  `initial_node_id`, `node_count`, `transition_count`. The list endpoint does not
  return the graph itself, so `nodes` is empty here — read `node_count` to size the
  flow instead.
- `flow templates show` prints a single template **with** its graph: `nodes` (an array of
  `{id, name, node_type, goal, prompt, child_ids, branch_rules, …}` — the node id is the
  `id` field, the CLI renders it keyed by that id but the JSON keeps the engine's array),
  `transitions` (list of `{id, from_id, to_id, condition}`), plus
  `on_done_template_id` and `on_reject_template_id`. This is the object to read to
  understand the workflow's shape.
- exit 0 for both. An empty array means this engine instance has no templates seeded —
  there is nothing to start, which is a real answer worth reporting.
- exit 1: `facet: <message>` on stderr (unknown `template-id` answers 404); no graph
  was returned.
