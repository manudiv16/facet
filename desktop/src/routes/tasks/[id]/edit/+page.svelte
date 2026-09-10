<script lang="ts">
	import { goto } from "$app/navigation";
	import { page } from "$app/stores";
	import TaskForm from "$lib/components/TaskForm.svelte";
	import type { TaskCreate } from "$lib/types";
	import {
		createTaskDetailStore,
		mutationError,
		tasks,
		updateTaskOptimistic,
	} from "$stores/tasks";

	// The `[id]` route guarantees the param at runtime; `!` matches that.
	const id = $page.params.id!;
	const detail = createTaskDetailStore(id);

	let busy = false;

	$: task = $detail.task;

	async function handleSubmit(event: CustomEvent<TaskCreate>) {
		busy = true;
		mutationError.set(null);
		try {
			const { title, description, priority, tags } = event.detail;
			// Level and parent are intentionally omitted: C6's PATCH ignores them.
			await updateTaskOptimistic(id, { title, description, priority, tags });
			await goto(`/tasks/${id}`);
		} catch {
			// Rolled back by updateTaskOptimistic; `mutationError` is shown.
		} finally {
			busy = false;
		}
	}
</script>

{#if $detail.loading && !task}
	<div class="state" role="status">Loading task…</div>
{:else if $detail.notFound}
	<div class="state state-error" role="alert">
		<p>Task not found.</p>
		<a href="/tasks">Back to tasks</a>
	</div>
{:else if task}
	<section class="edit-task">
		<nav class="breadcrumbs">
			<a href="/tasks">Tasks</a>
			<span aria-hidden="true">/</span>
			<a href={`/tasks/${task.id}`}>{task.short_id}</a>
			<span aria-hidden="true">/</span>
			<span>Edit</span>
		</nav>

		<h1>Edit task</h1>

		<TaskForm
			{task}
			tasks={$tasks}
			busy={busy}
			serverError={$mutationError}
			submitLabel="Save changes"
			lockStructure
			on:submit={handleSubmit}
		/>
	</section>
{/if}

<style>
	.edit-task {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-width: 720px;
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

	h1 {
		margin: 0;
		font-size: 1.5rem;
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
