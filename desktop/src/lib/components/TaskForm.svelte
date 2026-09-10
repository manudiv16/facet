<script lang="ts">
	import { createEventDispatcher } from "svelte";
	import {
		buildTaskSubmission,
		LEVELS,
		LEVEL_LABELS,
		PRIORITIES,
		PRIORITY_LABELS,
		type TaskFormErrors,
	} from "$lib/tasks-utils";
	import type { Task, TaskCreate, TaskLevel, TaskPriority } from "$lib/types";

	export let task: Task | undefined = undefined;
	export let tasks: Task[] = [];
	export let busy = false;
	export let serverError: string | null = null;
	export let submitLabel = "Create task";
	/** Level and parent are create-only: the C6 PATCH endpoint ignores them. */
	export let lockStructure = false;

	const dispatch = createEventDispatcher<{ submit: TaskCreate }>();

	let title = task?.title ?? "";
	let description = task?.description ?? "";
	let level = (task?.level ?? "task") as TaskLevel;
	let priority = (task?.priority ?? "medium") as TaskPriority;
	let parentId = task?.parent_id ?? "";
	let tagsText = (task?.tags ?? []).join(", ");
	let touched = false;
	let errors: TaskFormErrors = {};

	// Candidate parents: never allow a task to be its own parent.
	$: parentOptions = tasks.filter((item) => item.id !== task?.id);
	$: existingIds = new Set(tasks.map((item) => item.id));

	function parseTags(value: string): string[] {
		return value
			.split(",")
			.map((tag) => tag.trim())
			.filter((tag) => tag.length > 0);
	}

	function formInput() {
		return {
			title,
			description,
			level,
			priority,
			parent_id: parentId || null,
			tags: parseTags(tagsText),
		};
	}

	$: if (touched) {
		errors = buildTaskSubmission(formInput(), { existingIds }).errors;
	}

	function handleSubmit(event: SubmitEvent) {
		event.preventDefault();
		touched = true;
		const { errors: validationErrors, payload } = buildTaskSubmission(
			formInput(),
			{ existingIds },
		);
		errors = validationErrors;
		// Missing title / invalid enums never reach the network.
		if (!payload) return;

		dispatch("submit", payload);
	}
</script>

<form class="task-form" on:submit={handleSubmit} novalidate>
	{#if serverError}
		<div class="form-error-banner" role="alert">{serverError}</div>
	{/if}

	<div class="field">
		<label for="task-title">Title <span class="required">*</span></label>
		<input
			id="task-title"
			type="text"
			bind:value={title}
			class:invalid={errors.title}
			placeholder="Short, action-oriented title"
			aria-invalid={errors.title ? "true" : undefined}
			aria-describedby={errors.title ? "task-title-error" : undefined}
			disabled={busy}
		/>
		{#if errors.title}
			<p class="field-error" id="task-title-error">{errors.title}</p>
		{/if}
	</div>

	<div class="field">
		<label for="task-description">Description</label>
		<textarea
			id="task-description"
			bind:value={description}
			rows="4"
			placeholder="What needs to happen, and why"
			disabled={busy}
		></textarea>
	</div>

	<div class="field-row">
		<div class="field">
			<label for="task-level">Level <span class="required">*</span></label>
			<select id="task-level" bind:value={level} disabled={busy || lockStructure}>
				{#each LEVELS as option (option)}
					<option value={option}>{LEVEL_LABELS[option]}</option>
				{/each}
			</select>
			{#if errors.level}
				<p class="field-error">{errors.level}</p>
			{/if}
		</div>

		<div class="field">
			<label for="task-priority">Priority <span class="required">*</span></label>
			<select id="task-priority" bind:value={priority} disabled={busy}>
				{#each PRIORITIES as option (option)}
					<option value={option}>{PRIORITY_LABELS[option]}</option>
				{/each}
			</select>
			{#if errors.priority}
				<p class="field-error">{errors.priority}</p>
			{/if}
		</div>
	</div>

	<div class="field">
		<label for="task-parent">Parent</label>
		<select id="task-parent" bind:value={parentId} disabled={busy || lockStructure}>
			<option value="">No parent</option>
			{#each parentOptions as option (option.id)}
				<option value={option.id}>
					{option.short_id} · {option.title}
				</option>
			{/each}
		</select>
		{#if lockStructure}
			<p class="field-hint">
				Level and parent are set at creation and cannot be changed.
			</p>
		{/if}
		{#if errors.parent_id}
			<p class="field-error">{errors.parent_id}</p>
		{/if}
	</div>

	<div class="field">
		<label for="task-tags">Tags</label>
		<input
			id="task-tags"
			type="text"
			bind:value={tagsText}
			placeholder="comma, separated, tags"
			disabled={busy}
		/>
	</div>

	<div class="actions">
		<button type="submit" class="primary" disabled={busy}>
			{busy ? "Saving…" : submitLabel}
		</button>
		<slot name="actions" />
	</div>
</form>

<style>
	.task-form {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-width: 640px;
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.field-row {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 1rem;
	}

	label {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--text);
	}

	.required {
		color: #ef4444;
	}

	input,
	textarea,
	select {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.55rem 0.7rem;
		color: var(--text);
		font: inherit;
		font-size: 0.9rem;
	}

	input:focus,
	textarea:focus,
	select:focus {
		outline: 2px solid color-mix(in srgb, var(--accent) 55%, transparent);
		outline-offset: 1px;
		border-color: var(--accent);
	}

	input.invalid {
		border-color: #ef4444;
	}

	.field-error {
		margin: 0;
		color: #ef4444;
		font-size: 0.8rem;
	}

	.field-hint {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.78rem;
	}

	.form-error-banner {
		padding: 0.65rem 0.85rem;
		border-radius: 8px;
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
		font-size: 0.875rem;
	}

	.actions {
		display: flex;
		gap: 0.75rem;
		align-items: center;
	}

	button.primary {
		background: var(--accent);
		color: white;
		border: none;
		border-radius: 8px;
		padding: 0.55rem 1.1rem;
		font: inherit;
		font-weight: 600;
		cursor: pointer;
	}

	button.primary:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
</style>
