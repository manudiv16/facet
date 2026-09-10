<script lang="ts">
	import { createEventDispatcher } from "svelte";
	import TaskBadges from "$lib/components/TaskBadges.svelte";
	import type { Task } from "$lib/types";

	export let taskId: string;
	export let blockers: Task[] = [];
	export let candidates: Task[] = [];
	export let busy = false;
	export let loading = false;
	export let error: string | null = null;

	const dispatch = createEventDispatcher<{ add: string; remove: string }>();

	let selected = "";

	$: blockerIds = new Set(blockers.map((task) => task.id));
	$: options = candidates.filter(
		(task) => task.id !== taskId && !blockerIds.has(task.id),
	);

	function handleAdd() {
		if (!selected) return;
		dispatch("add", selected);
		selected = "";
	}
</script>

<section class="dependencies">
	<header>
		<h2>Dependencies</h2>
		<p class="hint">
			Blockers must be done before this task can appear in the ready queue.
		</p>
	</header>

	{#if error}
		<div class="error-banner" role="alert">{error}</div>
	{/if}

	{#if blockers.length > 0}
		<div class="blocked-banner" role="status">
			<span class="blocked-dot" aria-hidden="true"></span>
			<strong>Blocked</strong>
			<span>waiting on {blockers.length} task{blockers.length === 1 ? "" : "s"}</span>
		</div>
	{/if}

	{#if loading}
		<p class="muted">Loading blockers…</p>
	{:else if blockers.length === 0}
		<p class="muted">No blockers. This task is not waiting on anything.</p>
	{:else}
		<ul class="blocker-list">
			{#each blockers as blocker (blocker.id)}
				<li>
					<a class="blocker" href={`/tasks/${blocker.id}`}>
						<span class="short-id">{blocker.short_id}</span>
						<span class="blocker-title">{blocker.title}</span>
						<TaskBadges
							level={blocker.level}
							status={blocker.status}
							priority={blocker.priority}
							compact
						/>
					</a>
					<button
						type="button"
						class="remove"
						disabled={busy}
						on:click={() => dispatch("remove", blocker.id)}
					>
						Remove
					</button>
				</li>
			{/each}
		</ul>
	{/if}

	<div class="add-row">
		<select bind:value={selected} disabled={busy || options.length === 0}>
			<option value="">
				{options.length === 0 ? "No available tasks" : "Add a blocker…"}
			</option>
			{#each options as option (option.id)}
				<option value={option.id}>
					{option.short_id} · {option.title}
				</option>
			{/each}
		</select>
		<button
			type="button"
			class="add"
			disabled={busy || !selected}
			on:click={handleAdd}
		>
			Add
		</button>
	</div>
</section>

<style>
	.dependencies {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 1rem 1.15rem;
	}

	h2 {
		margin: 0;
		font-size: 1rem;
	}

	.hint {
		margin: 0.2rem 0 0;
		color: var(--text-muted);
		font-size: 0.82rem;
	}

	.error-banner {
		padding: 0.55rem 0.75rem;
		border-radius: 8px;
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
		font-size: 0.85rem;
	}

	.blocked-banner {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem 0.75rem;
		border-radius: 8px;
		background: rgba(239, 68, 68, 0.1);
		color: #ef4444;
		font-size: 0.85rem;
	}

	.blocked-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: #ef4444;
	}

	.blocker-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}

	.blocker-list li {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.blocker {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		flex: 1;
		min-width: 0;
		padding: 0.45rem 0.6rem;
		border-radius: 8px;
		border: 1px solid var(--border);
		background: var(--surface-2);
		text-decoration: none;
		color: var(--text);
	}

	.blocker:hover {
		border-color: var(--accent);
	}

	.short-id {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.75rem;
		color: var(--text-muted);
	}

	.blocker-title {
		flex: 1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 0.88rem;
	}

	.remove,
	.add {
		border: 1px solid var(--border);
		background: var(--surface-2);
		color: var(--text);
		border-radius: 8px;
		padding: 0.4rem 0.7rem;
		font: inherit;
		font-size: 0.82rem;
		cursor: pointer;
	}

	.remove:hover:not(:disabled),
	.add:hover:not(:disabled) {
		border-color: var(--accent);
	}

	.remove:disabled,
	.add:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.add-row {
		display: flex;
		gap: 0.5rem;
	}

	select {
		flex: 1;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.45rem 0.6rem;
		color: var(--text);
		font: inherit;
		font-size: 0.85rem;
	}

	.add {
		background: var(--accent);
		color: white;
		border-color: transparent;
		font-weight: 600;
	}

	.muted {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.85rem;
	}
</style>
