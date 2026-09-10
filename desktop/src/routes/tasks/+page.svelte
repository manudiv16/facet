<script lang="ts">
	import { onMount } from "svelte";
	import TaskBadges from "$lib/components/TaskBadges.svelte";
	import {
		LEVELS,
		LEVEL_LABELS,
		PRIORITIES,
		PRIORITY_LABELS,
		STATUSES,
		STATUS_LABELS,
	} from "$lib/tasks-utils";
	import type { TaskFilters } from "$lib/types";
	import {
		error,
		filters,
		loading,
		mutationError,
		readyIds,
		resetFilters,
		setFilter,
		taskRows,
		tasks,
		toggleCollapsed,
		collapsedIds,
		loadTasks,
	} from "$stores/tasks";

	onMount(() => {
		void loadTasks();
	});

	function onLevelChange(event: Event) {
		setFilter("level", (event.currentTarget as HTMLSelectElement).value as TaskFilters["level"]);
	}
	function onStatusChange(event: Event) {
		setFilter("status", (event.currentTarget as HTMLSelectElement).value as TaskFilters["status"]);
	}
	function onPriorityChange(event: Event) {
		setFilter("priority", (event.currentTarget as HTMLSelectElement).value as TaskFilters["priority"]);
	}
	function onSearchInput(event: Event) {
		setFilter("search", (event.currentTarget as HTMLInputElement).value);
	}
	function onReadyToggle(event: Event) {
		setFilter("readyOnly", (event.currentTarget as HTMLInputElement).checked);
	}

	$: hasFilters =
		$filters.level !== "all" ||
		$filters.status !== "all" ||
		$filters.priority !== "all" ||
		$filters.readyOnly ||
		$filters.search.trim() !== "";
</script>

<section class="tasks">
	<header class="page-header">
		<div>
			<h1>Tasks</h1>
			<p class="subtitle">
				{$tasks.length} task{$tasks.length === 1 ? "" : "s"} · {$taskRows.length}
				shown
			</p>
		</div>
		<a class="new-task" href="/tasks/new">New task</a>
	</header>

	{#if $mutationError}
		<div class="banner banner-error" role="alert">{$mutationError}</div>
	{/if}

	<div class="filters">
		<input
			class="search"
			type="search"
			placeholder="Search id, title or tag"
			value={$filters.search}
			on:input={onSearchInput}
			aria-label="Search tasks"
		/>

		<select value={$filters.level} on:change={onLevelChange} aria-label="Filter by level">
			<option value="all">All levels</option>
			{#each LEVELS as level (level)}
				<option value={level}>{LEVEL_LABELS[level]}</option>
			{/each}
		</select>

		<select value={$filters.status} on:change={onStatusChange} aria-label="Filter by status">
			<option value="all">All statuses</option>
			{#each STATUSES as status (status)}
				<option value={status}>{STATUS_LABELS[status]}</option>
			{/each}
		</select>

		<select value={$filters.priority} on:change={onPriorityChange} aria-label="Filter by priority">
			<option value="all">All priorities</option>
			{#each PRIORITIES as priority (priority)}
				<option value={priority}>{PRIORITY_LABELS[priority]}</option>
			{/each}
		</select>

		<label class="ready-toggle">
			<input type="checkbox" checked={$filters.readyOnly} on:change={onReadyToggle} />
			Ready only
		</label>

		{#if hasFilters}
			<button type="button" class="reset" on:click={resetFilters}>Reset</button>
		{/if}
	</div>

	{#if $loading}
		<div class="state" role="status">Loading tasks…</div>
	{:else if $error}
		<div class="state state-error" role="alert">
			<p>{$error}</p>
			<button type="button" on:click={() => loadTasks()}>Retry</button>
		</div>
	{:else if $tasks.length === 0}
		<div class="state">
			<p>No tasks yet.</p>
			<a class="new-task" href="/tasks/new">Create the first task</a>
		</div>
	{:else if $taskRows.length === 0}
		<div class="state">
			<p>No tasks match these filters.</p>
			<button type="button" on:click={resetFilters}>Clear filters</button>
		</div>
	{:else}
		<ul class="task-list">
			{#each $taskRows as row (row.task.id)}
				<li class="task-row" style:padding-left={`${row.depth * 1.5}rem`}>
					<span class="indent" aria-hidden="true"></span>
					{#if row.hasChildren}
						<button
							type="button"
							class="disclosure"
							aria-label={$filters.readyOnly ? "Collapse" : "Expand"}
							aria-expanded={!$collapsedIds.has(row.task.id)}
							on:click={() => toggleCollapsed(row.task.id)}
						>
							▾
						</button>
					{:else}
						<span class="disclosure-spacer" aria-hidden="true"></span>
					{/if}

					<a class="task-link" href={`/tasks/${row.task.id}`}>
						<span class="short-id">{row.task.short_id}</span>
						<span class="title">{row.task.title || "(untitled)"}</span>
					</a>

					{#if $readyIds.has(row.task.id)}
						<span class="ready-chip" title="No incomplete blockers">Ready</span>
					{/if}

					<TaskBadges
						level={row.task.level}
						status={row.task.status}
						priority={row.task.priority}
						compact
					/>

					{#if row.task.tags.length > 0}
						<span class="tags">
							{#each row.task.tags as tag (tag)}<span class="tag">#{tag}</span>{/each}
						</span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.tasks {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-width: 1100px;
	}

	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	h1 {
		margin: 0;
		font-size: 1.5rem;
	}

	.subtitle {
		margin: 0.25rem 0 0;
		color: var(--text-muted);
		font-size: 0.9rem;
	}

	.new-task {
		display: inline-block;
		background: var(--accent);
		color: white;
		text-decoration: none;
		border-radius: 8px;
		padding: 0.5rem 0.9rem;
		font-size: 0.875rem;
		font-weight: 600;
		white-space: nowrap;
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

	.filters {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
		align-items: center;
	}

	.filters select,
	.filters input[type="search"] {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.45rem 0.6rem;
		color: var(--text);
		font: inherit;
		font-size: 0.85rem;
	}

	.filters .search {
		flex: 1;
		min-width: 200px;
	}

	.ready-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.85rem;
		color: var(--text-muted);
	}

	.reset {
		border: 1px solid var(--border);
		background: transparent;
		color: var(--text-muted);
		border-radius: 8px;
		padding: 0.45rem 0.7rem;
		font: inherit;
		font-size: 0.85rem;
		cursor: pointer;
	}

	.reset:hover {
		color: var(--text);
		border-color: var(--accent);
	}

	.state {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.6rem;
		padding: 2rem;
		border: 1px dashed var(--border);
		border-radius: 12px;
		color: var(--text-muted);
	}

	.state p {
		margin: 0;
	}

	.state button {
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text);
		border-radius: 8px;
		padding: 0.45rem 0.8rem;
		font: inherit;
		cursor: pointer;
	}

	.state-error {
		border-color: rgba(239, 68, 68, 0.4);
		color: #ef4444;
	}

	.task-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.task-row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.45rem 0.6rem;
		border: 1px solid var(--border);
		border-radius: 8px;
		background: var(--surface-1);
	}

	.task-row:hover {
		background: var(--surface-2);
	}

	.disclosure,
	.disclosure-spacer {
		width: 1.4rem;
		flex: 0 0 1.4rem;
		text-align: center;
	}

	.disclosure {
		border: none;
		background: transparent;
		color: var(--text-muted);
		cursor: pointer;
		font: inherit;
		padding: 0;
	}

	.task-link {
		display: flex;
		align-items: baseline;
		gap: 0.5rem;
		min-width: 0;
		flex: 1 1 320px;
		text-decoration: none;
		color: var(--text);
	}

	.task-link:hover .title {
		text-decoration: underline;
	}

	.short-id {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.75rem;
		color: var(--text-muted);
	}

	.title {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 0.9rem;
	}

	.ready-chip {
		font-size: 0.68rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: #22c55e;
		border: 1px solid rgba(34, 197, 94, 0.4);
		background: rgba(34, 197, 94, 0.1);
		border-radius: 999px;
		padding: 0.05rem 0.4rem;
	}

	.tags {
		display: inline-flex;
		gap: 0.3rem;
		flex-wrap: wrap;
	}

	.tag {
		font-size: 0.72rem;
		color: var(--text-muted);
		background: var(--surface-2);
		border-radius: 6px;
		padding: 0.05rem 0.35rem;
	}
</style>
