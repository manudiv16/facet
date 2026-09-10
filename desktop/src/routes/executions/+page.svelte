<script lang="ts">
	// Execution history and session log viewer (F6).
	//
	// The page is a per-task history viewer: pick a task (or deep-link with
	// `?task=`), and ExecutionHistory renders one row per step with token/cost
	// metrics and a selectable session log. When no task is selected the page
	// shows the live "active" executions overview (running + awaiting_input),
	// clicking one of which binds the selection to its task.
	import { onMount, onDestroy } from "svelte";
	import { goto } from "$app/navigation";
	import { page } from "$app/stores";
	import ExecutionHistory from "$lib/components/ExecutionHistory.svelte";
	import { createActiveExecutionsStore } from "$lib/stores";
	import {
		formatCost,
		formatDuration,
		formatNumber,
		formatTimestamp,
	} from "$lib/format";
	import type { Execution, ExecutionStatus } from "$lib/types";
	import { loadTasks, tasks } from "$stores/tasks";

	const active = createActiveExecutionsStore();
	const { executions: activeExecutions, loading: activeLoading, error: activeError } = active;

	let taskId = "";
	let manualTaskId = "";

	onMount(() => {
		void loadTasks();
		void active.load();
		const fromUrl = $page.url.searchParams.get("task");
		if (fromUrl) selectTask(fromUrl, false);
	});

	onDestroy(() => {
		active.destroy();
	});

	function selectTask(id: string, syncUrl = true): void {
		const next = id.trim();
		if (next === taskId) return;
		// The overview store must not keep polling while a task history is shown.
		active.destroy();
		taskId = next;
		if (syncUrl) {
			void goto(`/executions?task=${encodeURIComponent(next)}`, {
				replaceState: true,
				keepFocus: true,
				noScroll: true,
			});
		}
	}

	function clearTask(): void {
		if (!taskId) return;
		selectTask("", true);
		void active.load();
	}

	function onTaskSelect(event: Event): void {
		selectTask((event.currentTarget as HTMLSelectElement).value);
	}

	function onManualTask(event: Event): void {
		selectTask((event.currentTarget as HTMLInputElement).value);
	}

	function openExecution(execution: Execution): void {
		if (execution.task_id) selectTask(execution.task_id);
	}

	$: title = $tasks.find((task) => task.id === taskId)?.title ?? null;

	function statusClass(status: ExecutionStatus): string {
		switch (status) {
			case "completed":
				return "ok";
			case "failed":
			case "rejected":
				return "bad";
			case "in_progress":
			case "running":
			case "entered":
			case "awaiting_input":
				return "active";
			default:
				return "pending";
		}
	}
</script>

<svelte:head><title>Executions · Facet</title></svelte:head>

<section class="executions">
	<header class="page-head">
		<div>
			<h1>Executions</h1>
			<p class="subtitle">
				Step execution history with tokens, cost and duration — one row per
				step, newest first. Select a row to inspect its session log.
			</p>
		</div>
	</header>

	<div class="toolbar">
		<label for="task-select">Task</label>
		{#if $tasks.length > 0}
			<select id="task-select" value={taskId} on:change={onTaskSelect}>
				<option value="">Select a task…</option>
				{#each $tasks as task (task.id)}
					<option value={task.id}>{task.short_id} · {task.title}</option>
				{/each}
			</select>
		{:else}
			<input
				id="task-select"
				type="text"
				placeholder="Task id…"
				value={manualTaskId}
				on:change={onManualTask}
				aria-label="Task id"
			/>
		{/if}
		{#if taskId}
			<span class="muted">
				history for <code>{taskId}</code>{title ? ` — ${title}` : ""}
			</span>
			<button type="button" class="btn btn-ghost" on:click={clearTask}>
				Clear
			</button>
		{/if}
	</div>

	{#if taskId}
		{#key taskId}
			<ExecutionHistory {taskId} />
		{/key}
	{:else if $activeLoading}
		<p class="state">Loading active executions…</p>
	{:else}
		<section class="overview">
			<div class="overview-head">
				<h2>Active executions</h2>
				<p class="subtitle">
					Steps currently running or awaiting input across tasks. Select one to
					open its task history and session log.
				</p>
			</div>

			{#if $activeError}
				<p class="banner banner-error" role="alert">{$activeError}</p>
			{/if}

			{#if $activeExecutions.length === 0}
				<p class="state">
					{$activeError
						? "Active executions could not be loaded."
						: "No execution is running right now. Pick a task above to browse its history."}
				</p>
			{:else}
				<div class="table-wrap">
					<table>
						<thead>
							<tr>
								<th scope="col">Task</th>
								<th scope="col">Node</th>
								<th scope="col">Status</th>
								<th scope="col">Model</th>
								<th scope="col" class="num">Input</th>
								<th scope="col" class="num">Output</th>
								<th scope="col" class="num">Cost</th>
								<th scope="col">Duration</th>
								<th scope="col">Started</th>
							</tr>
						</thead>
						<tbody>
							{#each $activeExecutions as execution (execution.id)}
								<tr>
									<td class="node">
										<button
											type="button"
											class="node-link"
											on:click={() => openExecution(execution)}
										>
											{execution.task_id || "—"}
										</button>
									</td>
									<td>{execution.node_id || "—"}</td>
									<td>
										<span class="badge badge-{statusClass(execution.status)}">
											{execution.status.replace("_", " ")}
										</span>
									</td>
									<td class="model">{execution.model || "—"}</td>
									<td class="num">{formatNumber(execution.input_tokens)}</td>
									<td class="num">{formatNumber(execution.output_tokens)}</td>
									<td class="num cost">{formatCost(execution.cost)}</td>
									<td>{formatDuration(execution.duration_ms)}</td>
									<td class="time">{formatTimestamp(execution.started_at)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</section>
	{/if}
</section>

<style>
	.executions {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}

	.page-head h1 {
		margin: 0 0 0.25rem;
		font-size: 1.5rem;
	}

	.subtitle {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.9rem;
	}

	.toolbar {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		flex-wrap: wrap;
	}

	.toolbar label {
		font-size: 0.85rem;
		font-weight: 600;
	}

	select,
	input[type="text"] {
		padding: 0.5rem 0.7rem;
		border-radius: 8px;
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text);
		font-size: 0.9rem;
		min-width: 260px;
	}

	.muted {
		color: var(--text-muted);
		font-size: 0.85rem;
	}

	.btn {
		padding: 0.45rem 0.8rem;
		border-radius: 8px;
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text);
		font-size: 0.82rem;
		font-weight: 600;
		cursor: pointer;
	}

	.btn-ghost:hover {
		background: var(--surface-2);
	}

	.banner {
		margin: 0 0 0.75rem;
		padding: 0.7rem 1rem;
		border-radius: 8px;
		font-size: 0.88rem;
	}

	.banner-error {
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
	}

	.state {
		padding: 1.5rem;
		text-align: center;
		color: var(--text-muted);
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
	}

	.overview {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}

	.overview-head h2 {
		margin: 0 0 0.25rem;
		font-size: 1.15rem;
	}

	.table-wrap {
		overflow-x: auto;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.875rem;
	}

	th,
	td {
		padding: 0.55rem 0.75rem;
		text-align: left;
		border-bottom: 1px solid var(--border);
		white-space: nowrap;
	}

	thead th {
		color: var(--text-muted);
		font-weight: 600;
		background: var(--surface-2);
		position: sticky;
		top: 0;
	}

	tbody tr:hover {
		background: var(--surface-2);
	}

	.num {
		text-align: right;
		font-variant-numeric: tabular-nums;
	}

	.cost {
		font-variant-numeric: tabular-nums;
	}

	.time {
		color: var(--text-muted);
		font-size: 0.8rem;
	}

	.model {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.8rem;
	}

	.node-link {
		padding: 0;
		border: none;
		background: none;
		color: var(--accent);
		font: inherit;
		font-weight: 600;
		cursor: pointer;
		text-align: left;
	}

	.node-link:hover {
		text-decoration: underline;
	}

	.badge {
		display: inline-block;
		padding: 0.12rem 0.5rem;
		border-radius: 999px;
		font-size: 0.72rem;
		font-weight: 600;
		text-transform: capitalize;
	}

	.badge-ok {
		background: rgba(34, 197, 94, 0.15);
		color: #16a34a;
	}

	.badge-bad {
		background: rgba(239, 68, 68, 0.15);
		color: #ef4444;
	}

	.badge-active {
		background: rgba(59, 130, 246, 0.15);
		color: var(--accent);
	}

	.badge-pending {
		background: var(--surface-3);
		color: var(--text-muted);
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.82em;
	}
</style>
