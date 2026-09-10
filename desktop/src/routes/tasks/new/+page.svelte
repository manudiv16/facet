<script lang="ts">
	import { onMount } from "svelte";
	import { goto } from "$app/navigation";
	import TaskForm from "$lib/components/TaskForm.svelte";
	import type { TaskCreate } from "$lib/types";
	import {
		createTaskOptimistic,
		loadTasks,
		mutationError,
		tasks,
	} from "$stores/tasks";

	let busy = false;

	onMount(() => {
		mutationError.set(null);
		if ($tasks.length === 0) void loadTasks();
	});

	async function handleSubmit(event: CustomEvent<TaskCreate>) {
		busy = true;
		mutationError.set(null);
		try {
			const created = await createTaskOptimistic(event.detail);
			await goto(`/tasks/${created.id}`);
		} catch {
			// createTaskOptimistic rolled back the phantom row and set
			// `mutationError`; stay on the form so the user can retry.
		} finally {
			busy = false;
		}
	}
</script>

<section class="new-task">
	<nav class="breadcrumbs">
		<a href="/tasks">Tasks</a>
		<span aria-hidden="true">/</span>
		<span>New</span>
	</nav>

	<h1>New task</h1>

	<TaskForm
		tasks={$tasks}
		busy={busy}
		serverError={$mutationError}
		submitLabel="Create task"
		on:submit={handleSubmit}
	/>
</section>

<style>
	.new-task {
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
</style>
