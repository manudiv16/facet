<script lang="ts">
	import { onDestroy } from "svelte";
	import { goto } from "$app/navigation";
	import { page } from "$app/stores";
	import DependencyEditor from "$lib/components/DependencyEditor.svelte";
	import TaskBadges from "$lib/components/TaskBadges.svelte";
	import {
		formatTimestamp,
		PRIORITIES,
		PRIORITY_LABELS,
		STATUSES,
		STATUS_LABELS,
	} from "$lib/tasks-utils";
	import type { TaskPriority, TaskStatus } from "$lib/types";
	import { archiveTaskOptimistic, createTaskDetailStore, tasks } from "$stores/tasks";

	// The `[id]` route guarantees the param at runtime; `!` matches that.
	let id = $page.params.id!;
	let detail = createTaskDetailStore(id);

	// Support navigating between tasks (e.g. via a blocker link) without a
	// full remount by rebuilding the detail store when the param changes.
	$: if ($page.params.id !== id) {
		id = $page.params.id!;
		detail = createTaskDetailStore(id);
	}

	let archiveBusy = false;

	async function changeStatus(event: Event) {
		const value = (event.currentTarget as HTMLSelectElement).value as TaskStatus;
		try {
			await detail.update({ status: value });
		} catch {
			// mutationError surfaces the server message inline.
		}
	}

	async function changePriority(event: Event) {
		const value = (event.currentTarget as HTMLSelectElement)
			.value as TaskPriority;
		try {
			await detail.update({ priority: value });
		} catch {
			// mutationError surfaces the server message inline.
		}
	}

	async function handleAdd(event: CustomEvent<string>) {
		try {
			await detail.addBlocker(event.detail);
		} catch {
			// mutationError surfaces the server message inline.
		}
	}

	async function handleRemove(event: CustomEvent<string>) {
		try {
			await detail.removeBlocker(event.detail);
		} catch {
			// mutationError surfaces the server message inline.
		}
	}

	async function archive() {
		archiveBusy = true;
		try {
			await archiveTaskOptimistic(id);
			await goto("/tasks");
		} catch {
			// mutationError surfaces the server message inline.
		} finally {
			archiveBusy = false;
		}
	}

	onDestroy(() => {
		// Nothing to tear down: no polling in the detail store.
	});

	$: task = $detail.task;
	$: candidateParents = $tasks;
</script>

{#if $detail.loading && !task}
	<div class="state" role="status">Loading task…</div>
{:else if $detail.notFound}
	<div class="state state-error" role="alert">
		<p>Task not found.</p>
		<a href="/tasks">Back to tasks</a>
	</div>
{:else if $detail.error && !task}
	<div class="state state-error" role="alert">
		<p>{$detail.error}</p>
		<a href="/tasks">Back to tasks</a>
	</div>
{:else if task}
	<section class="detail">
		<nav class="breadcrumbs">
			<a href="/tasks">Tasks</a>
			<span aria-hidden="true">/</span>
			<span class="crumb-current">{task.short_id}</span>
		</nav>

		{#if $detail.mutationError}
			<div class="banner banner-error" role="alert">{$detail.mutationError}</div>
		{/if}

		<header class="detail-header">
			<div class="heading">
				<h1>{task.title || "(untitled)"}</h1>
				<div class="meta">
					<TaskBadges level={task.level} status={task.status} priority={task.priority} />
					<span class="muted">Updated {formatTimestamp(task.updated_at)}</span>
				</div>
			</div>
			<div class="header-actions">
				<a class="button" href={`/tasks/${task.id}/edit`}>Edit</a>
				<button
					type="button"
					class="button danger"
					disabled={archiveBusy}
					on:click={archive}
				>
					{archiveBusy ? "Archiving…" : "Archive"}
				</button>
			</div>
		</header>

		<div class="grid">
			<article class="panel description">
				<h2>Description</h2>
				{#if task.description.trim()}
					<p class="description-text">{task.description}</p>
				{:else}
					<p class="muted">No description.</p>
				{/if}

				<h2>Tags</h2>
				{#if task.tags.length > 0}
					<div class="tags">
						{#each task.tags as tag (tag)}<span class="tag">#{tag}</span>{/each}
					</div>
				{:else}
					<p class="muted">No tags.</p>
				{/if}
			</article>

			<article class="panel">
				<h2>Status &amp; priority</h2>
				<div class="inline-fields">
					<label>
						Status
						<select value={task.status} on:change={changeStatus}>
							{#each STATUSES as status (status)}
								<option value={status}>{STATUS_LABELS[status]}</option>
							{/each}
						</select>
					</label>
					<label>
						Priority
						<select value={task.priority} on:change={changePriority}>
							{#each PRIORITIES as priority (priority)}
								<option value={priority}>{PRIORITY_LABELS[priority]}</option>
							{/each}
						</select>
					</label>
				</div>

				<h2>Flow position</h2>
				{#if task.flow_instance_id || task.current_node_id}
					<dl class="flow">
						{#if task.flow_instance_id}
							<dt>Instance</dt>
							<dd><code>{task.flow_instance_id}</code></dd>
						{/if}
						{#if task.current_node_id}
							<dt>Node</dt>
							<dd><code>{task.current_node_id}</code></dd>
						{/if}
					</dl>
				{:else}
					<p class="muted">No active flow.</p>
				{/if}
			</article>

			<article class="panel sections">
				<h2>Sections</h2>
				{#if !$detail.sectionsAvailable}
					<p class="muted">Sections are not exposed by this Crystalline build.</p>
				{:else if $detail.sections.length === 0}
					<p class="muted">No sections.</p>
				{:else}
					<ul class="section-list">
						{#each $detail.sections as section (section.id)}
							<li>
								<span class="section-type">{section.section_type}</span>
								<p>{section.content}</p>
							</li>
						{/each}
					</ul>
				{/if}
			</article>

			<DependencyEditor
				taskId={task.id}
				blockers={$detail.blockers}
				candidates={candidateParents}
				loading={$detail.blockersLoading}
				busy={false}
				error={null}
				on:add={handleAdd}
				on:remove={handleRemove}
			/>
		</div>
	</section>
{/if}

<style>
	.detail {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-width: 1000px;
	}

	.breadcrumbs {
		display: flex;
		gap: 0.4rem;
		color: var(--text-muted);
		font-size: 0.85rem;
	}

	.breadcrumbs a {
		color: var(--accent);
		text-decoration: none;
	}

	.crumb-current {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
	}

	.banner {
		padding: 0.65rem 0.85rem;
		border-radius: 8px;
		font-size: 0.875rem;
	}

	.banner-error {
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
	}

	.detail-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	.heading h1 {
		margin: 0 0 0.5rem;
		font-size: 1.5rem;
	}

	.meta {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		flex-wrap: wrap;
	}

	.header-actions {
		display: flex;
		gap: 0.5rem;
	}

	.button {
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text);
		border-radius: 8px;
		padding: 0.45rem 0.8rem;
		font: inherit;
		font-size: 0.85rem;
		text-decoration: none;
		cursor: pointer;
	}

	.button:hover {
		border-color: var(--accent);
	}

	.button.danger {
		color: #ef4444;
	}

	.button:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
		gap: 1rem;
		align-items: start;
	}

	.panel {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 1rem 1.15rem;
	}

	.panel h2 {
		margin: 0 0 0.6rem;
		font-size: 1rem;
	}

	.panel h2:not(:first-child) {
		margin-top: 1.1rem;
	}

	.description {
		grid-column: 1 / -1;
	}

	.description-text {
		margin: 0;
		white-space: pre-wrap;
		line-height: 1.5;
	}

	.sections {
		grid-column: 1 / -1;
	}

	.tags {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
	}

	.tag {
		font-size: 0.75rem;
		color: var(--text-muted);
		background: var(--surface-2);
		border-radius: 6px;
		padding: 0.1rem 0.4rem;
	}

	.inline-fields {
		display: flex;
		gap: 0.75rem;
		flex-wrap: wrap;
	}

	.inline-fields label {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 0.8rem;
		color: var(--text-muted);
	}

	select {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.45rem 0.6rem;
		color: var(--text);
		font: inherit;
		font-size: 0.85rem;
	}

	.flow {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: 0.3rem 0.75rem;
		margin: 0;
		font-size: 0.85rem;
	}

	.flow dt {
		color: var(--text-muted);
	}

	.flow dd {
		margin: 0;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.85em;
	}

	.section-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}

	.section-type {
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--accent);
	}

	.section-list p {
		margin: 0.2rem 0 0;
		white-space: pre-wrap;
	}

	.muted {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.85rem;
	}

	.state {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		padding: 2rem;
		border: 1px dashed var(--border);
		border-radius: 12px;
		color: var(--text-muted);
	}

	.state a {
		color: var(--accent);
	}

	.state-error {
		border-color: rgba(239, 68, 68, 0.4);
		color: #ef4444;
	}
</style>
