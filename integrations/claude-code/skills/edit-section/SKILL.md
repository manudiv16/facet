---
name: edit-section
description: Read a Crystalline task's sections and append a new one through the facet CLI. In-place section edits are pending crystalline#16 — use only when the user wants section content reviewed or a section added.
status: pending
---

# Edit a section (pending)

## Status

**Pending — the in-place edit half of this skill is blocked by crystalline#16.** The
CLI exposes reading (`task sections`) and appending (`task section add`), but no
section update: neither the CLI nor the engine route
`PATCH /api/v1/tasks/:id/sections/:section_id` exists yet. Never fake an edit with
another command and never report a section as changed — say it is unsupported on this
build and what the planned command will be.

## When to use

The user wants a task's structured description reviewed, or a new section added. If
they want an existing section's text changed, read it, explain the limitation above,
and offer to append a replacement section instead (that leaves the original in place).

## Read the current sections

```bash
facet --json task sections <task-id>
```

An array of `{id, task_id, section_type, content, order}`; `[]` means no sections are
stored. Exit 1 means the read failed (the sections API ships with crystalline#16) —
the task's sections are unknown, not empty.

## Append a section (not an edit)

```bash
facet --json task section add <task-id> --type testing_criterion --content "gleam test and npm test stay green"
```

`--type` accepts `goal`, `context`, `current_behavior`, `desired_behavior`,
`checklist_item`, `testing_criterion`, `constraint`, `anti_pattern`, `failure_test`;
`--content` is the section text. stdout is the created section object with its
`id`, `task_id` and `order`. Exit 1 means nothing was written.

## Planned command

```text
PENDING (blocked by crystalline#16 — no CLI command yet):
facet --json task section update <task-id> <section-id> --content "<new text>"
```
