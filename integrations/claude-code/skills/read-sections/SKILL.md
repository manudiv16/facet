---
name: read-sections
description: Read a Crystalline task's structured sections (goal, context, constraints, testing criteria) through the facet CLI. Use when the user asks what a task's spec says or wants its structured description.
status: active
---

# Read sections

## When to use

A task's description is split into typed sections — the goal, the context, the desired
behaviour, testing criteria — and the user wants that structured spec rather than the
one-line title. For changing a section see `edit-section`.

## Command

```bash
facet --json task sections <task-id>
```

## Interpreting the output

- stdout is a JSON **array** of section objects: `id`, `task_id`, `section_type`,
  `content`, `order`. `section_type` is one of `goal`, `context`, `current_behavior`,
  `desired_behavior`, `checklist_item`, `testing_criterion`, `constraint`,
  `anti_pattern`, `failure_test`. Sort by `order` to reconstruct the intended reading
  order; `[]` means the engine holds no sections for the task.
- exit 0 means the read succeeded. exit 1 means it did not, and the array is absent —
  report the failure instead of saying the task has no sections.
- **Engine prerequisite:** `GET /api/v1/tasks/:id/sections` ships with crystalline#16.
  On an older Crystalline build the route answers 404 and `facet` exits 1 with the
  engine's body (`{"error":"not_found",…}`) on stderr. Say the sections API is missing
  from this build; do not fall back to scraping `task show`.
