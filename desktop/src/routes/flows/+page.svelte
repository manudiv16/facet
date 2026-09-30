<script lang="ts">
	import { onMount } from "svelte";
	import { get } from "svelte/store";
	import { goto } from "$app/navigation";
	import { page } from "$app/stores";
	import FlowControls from "$lib/components/FlowControls.svelte";
	import FlowGraph from "$lib/components/FlowGraph.svelte";
	import TemplatePicker from "$lib/components/TemplatePicker.svelte";
	import {
		templateNodeCount,
		templateTransitionCount,
	} from "$lib/flow-model";
	import { createFlowStore, createTemplatesStore } from "$lib/flow-stores";
	import type { FlowTemplate } from "$lib/types";
	import { loadTasks, tasks } from "$stores/tasks";

	// Svelte auto-subscription needs the individual stores, not the container.
	const flow = createFlowStore();
	const {
		state: flowState,
		action: flowAction,
		actionLog,
		loading: flowLoading,
		busy: flowBusy,
		error: flowError,
		nodeStatuses,
		currentNodeId,
		awaitingInput,
		terminal,
		currentStep,
	} = flow;

	const {
		templates,
		loading: templatesLoading,
		error: templatesError,
		usingFallback,
		load: loadTemplates,
	} = createTemplatesStore();

	let taskId = "";
	let manualTaskId = "";
	let pickerOpen = false;
	let selectedNodeId: string | null = null;

	onMount(() => {
		void loadTemplates();
		void loadTasks();
		const fromUrl = $page.url.searchParams.get("task");
		if (fromUrl) selectTask(fromUrl, false);
	});

	function selectTask(id: string, syncUrl = true): void {
		const next = id.trim();
		taskId = next;
		selectedNodeId = null;
		if (!next) {
			flow.reset();
			return;
		}
		void flow.load(next);
		if (syncUrl) {
			void goto(`/flows?task=${encodeURIComponent(next)}`, {
				replaceState: true,
				keepFocus: true,
				noScroll: true,
			});
		}
	}

	function onTaskSelect(event: Event): void {
		selectTask((event.currentTarget as HTMLSelectElement).value);
	}

	function onManualTask(event: Event): void {
		selectTask((event.currentTarget as HTMLInputElement).value);
	}

	async function handlePick(template: FlowTemplate): Promise<void> {
		pickerOpen = false;
		if (!taskId) return;
		await flow.start(template.slug);
		// Surface the first engine Action immediately.
		if (get(flowState)) await flow.advance();
	}

	$: instance = $flowState?.flow_instance ?? null;
	$: templateMeta = instance
		? templates_list($templates, instance.template_id)
		: undefined;
	$: activeTemplate = instance
		? ({
				id: instance.template_id,
				slug: instance.template_id,
				name: templateMeta?.name ?? instance.template_id,
				description: templateMeta?.description ?? "",
				initial_node_id: instance.initial_node_id,
				nodes: instance.nodes,
				transitions: instance.transitions,
			} satisfies FlowTemplate)
		: null;
	$: selectedNode =
		selectedNodeId && instance
			? (instance.nodes.find((node) => node.id === selectedNodeId) ?? null)
			: null;
	$: iterations = $flowState?.loop_counters ?? {};

	function templates_list(
		list: FlowTemplate[],
		slug: string,
	): FlowTemplate | undefined {
		return list.find((template) => template.slug === slug);
	}

	function onSelectNode(nodeId: string): void {
		selectedNodeId = selectedNodeId === nodeId ? null : nodeId;
	}

	function formatTime(timestamp: number): string {
		return new Date(timestamp).toLocaleTimeString();
	}
</script>

<svelte:head><title>Flows · Facet</title></svelte:head>

<section class="flows">
	<header class="page-head">
		<div>
			<h1>Flows</h1>
			<p class="subtitle">
				Render flow templates, highlight the running node, and drive execution
				step by step.
			</p>
		</div>
		<div class="head-actions">
			<a class="btn" href="/flows/templates">Templates &amp; authoring</a>
			<button
				type="button"
				class="btn btn-primary"
				on:click={() => (pickerOpen = true)}
			>
				Choose template
			</button>
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
			<span class="muted">flow bound to <code>{taskId}</code></span>
		{/if}
	</div>

	{#if $flowError}
		<p class="banner banner-error" role="alert">{$flowError}</p>
	{/if}
	{#if $templatesError}
		<p class="banner banner-info">
			Template API unavailable ({$templatesError}); showing seeded slugs.
		</p>
	{/if}

	{#if !taskId}
		<section class="catalogue">
			<h2>Seeded templates</h2>
			<p class="subtitle">
				Select a task above, then start one of these templates. Slugs match the
				engine registry.
			</p>
			<ul class="cards">
				{#each $templates as template (template.slug)}
					<li class="card">
						<code class="slug">{template.slug}</code>
						<strong>{template.name}</strong>
						<p class="desc">{template.description}</p>
						<span class="meta">
							{templateNodeCount(template)} nodes · {templateTransitionCount(template)} edges
						</span>
					</li>
				{/each}
			</ul>
		</section>
	{:else if $flowLoading}
		<p class="state">Loading flow…</p>
	{:else if !$flowState}
		<section class="catalogue">
			<h2>No flow running on this task</h2>
			<p class="subtitle">Pick a template to instantiate a flow instance.</p>
			<ul class="cards">
				{#each $templates as template (template.slug)}
					<li class="card">
						<code class="slug">{template.slug}</code>
						<strong>{template.name}</strong>
						<p class="desc">{template.description}</p>
						<button type="button" class="btn" on:click={() => handlePick(template)}>
							Start {template.slug}
						</button>
					</li>
				{/each}
			</ul>
		</section>
	{:else if activeTemplate}
		<section class="running">
			<div class="running-head">
				<div>
					<h2>{activeTemplate.name}</h2>
					<p class="subtitle">
						<code>{activeTemplate.slug}</code>
						{activeTemplate.description ? `— ${activeTemplate.description}` : ""}
					</p>
				</div>
				<div class="head-actions">
					{#if $awaitingInput}
						<span class="pill pill-warn">awaiting input</span>
					{:else if $terminal}
						<span class="pill">finished</span>
					{/if}
					<button
						type="button"
						class="btn"
						disabled={$flowBusy}
						on:click={() => flow.unassign()}
					>
						Unassign flow
					</button>
				</div>
			</div>
			<p class="muted">
				Unassign deletes the instance once the execution is terminal; the engine
				refuses with 409 while it is pending, running or awaiting input — reject it
				first.
			</p>

			<FlowGraph
				template={activeTemplate}
				nodeStatuses={$nodeStatuses}
				currentNodeId={$currentNodeId}
				iterationCounters={iterations}
				selectedNodeId={selectedNodeId}
				onSelectNode={onSelectNode}
			/>

			<div class="detail-grid">
				<FlowControls
					state={$flowState}
					action={$flowAction}
					busy={$flowBusy}
					awaitingInput={$awaitingInput}
					terminal={$terminal}
					currentStep={$currentStep}
					onAdvance={() => flow.advance()}
					onComplete={(output) => flow.complete(output)}
					onProvideInput={(input) => flow.input(input)}
					onReject={(reason) => flow.reject(reason)}
				/>

				<aside class="inspector">
					{#if selectedNode}
						<h3>{selectedNode.name}</h3>
						<p class="node-type">{selectedNode.node_type}</p>
						<p class="goal">{selectedNode.goal}</p>
						{#if selectedNode.prompt}
							<h4>Prompt</h4>
							<pre>{selectedNode.prompt}</pre>
						{/if}
						{#if selectedNode.branch_rules.length > 0}
							<h4>Branch rules</h4>
							<ul>
								{#each selectedNode.branch_rules as rule (rule.target_id)}
									<li><code>{rule.condition}</code> → <code>{rule.target_id}</code></li>
								{/each}
							</ul>
						{/if}
						{#if selectedNode.loop_config}
							<h4>Loop</h4>
							<p>
								max <code>{selectedNode.loop_config.max_iterations ?? "∞"}</code>
								{#if selectedNode.loop_config.exit_condition}
									· exit <code>{selectedNode.loop_config.exit_condition}</code>
								{/if}
							</p>
						{/if}
						{#if selectedNode.child_ids.length > 0}
							<h4>Children</h4>
							<p>{selectedNode.child_ids.join(", ")}</p>
						{/if}
					{:else}
						<h3>Inspector</h3>
						<p class="muted">Select a node in the graph to inspect its config.</p>
					{/if}
				</aside>
			</div>

			<details class="action-log" open={$actionLog.length > 0}>
				<summary>Action history ({$actionLog.length})</summary>
				{#if $actionLog.length === 0}
					<p class="muted">No engine actions yet.</p>
				{:else}
					<ol>
						{#each [...$actionLog].reverse() as entry (entry.at + entry.action.kind)}
							<li>
								<span class="log-time">{formatTime(entry.at)}</span>
								<code class="log-kind">{entry.action.kind}</code>
							</li>
						{/each}
					</ol>
				{/if}
			</details>
		</section>
	{/if}
</section>

<TemplatePicker
	templates={$templates}
	open={pickerOpen}
	loading={$templatesLoading}
	error={$templatesError}
	usingFallback={$usingFallback}
	onSelect={handlePick}
	onClose={() => (pickerOpen = false)}
/>

<style>
	.flows {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}

	.page-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	h1 {
		margin: 0 0 0.25rem;
		font-size: 1.5rem;
	}

	h2 {
		margin: 0 0 0.25rem;
		font-size: 1.15rem;
	}

	.subtitle {
		margin: 0;
		color: var(--text-muted, #5f6b7a);
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
		border: 1px solid var(--border, #d3d9e1);
		background: var(--surface-1, #fff);
		color: var(--text, #1a2230);
		font-size: 0.9rem;
		min-width: 260px;
	}

	.muted {
		color: var(--text-muted, #5f6b7a);
		font-size: 0.85rem;
	}

	.banner {
		margin: 0;
		padding: 0.7rem 1rem;
		border-radius: 8px;
		font-size: 0.88rem;
	}

	.banner-error {
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
	}

	.banner-info {
		border: 1px solid color-mix(in srgb, var(--accent, #3b82f6) 45%, transparent);
		background: color-mix(in srgb, var(--accent, #3b82f6) 10%, transparent);
		color: var(--accent, #3b82f6);
	}

	.state {
		padding: 1.5rem;
		text-align: center;
		color: var(--text-muted, #5f6b7a);
	}

	.cards {
		list-style: none;
		margin: 0.75rem 0 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
		gap: 0.85rem;
	}

	.card {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		padding: 0.9rem 1rem;
		border-radius: 10px;
		border: 1px solid var(--border, #d3d9e1);
		background: var(--surface-1, #fff);
	}

	.slug {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.78rem;
		font-weight: 700;
		color: var(--accent, #3b82f6);
	}

	.desc {
		margin: 0;
		font-size: 0.82rem;
		color: var(--text-muted, #5f6b7a);
	}

	.meta {
		font-size: 0.75rem;
		color: var(--text-muted, #5f6b7a);
	}

	.running {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}

	.running-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	.head-actions {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		flex-wrap: wrap;
	}

	.pill {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		font-weight: 700;
		padding: 0.25rem 0.55rem;
		border-radius: 999px;
		border: 1px solid var(--border, #d3d9e1);
		color: var(--text-muted, #5f6b7a);
	}

	.pill-warn {
		border-color: rgba(249, 115, 22, 0.55);
		color: #f97316;
	}

	.detail-grid {
		display: grid;
		grid-template-columns: minmax(0, 2fr) minmax(240px, 1fr);
		gap: 1rem;
		align-items: start;
	}

	@media (max-width: 900px) {
		.detail-grid {
			grid-template-columns: 1fr;
		}
	}

	.inspector {
		padding: 0.9rem 1rem;
		border-radius: 10px;
		border: 1px solid var(--border, #d3d9e1);
		background: var(--surface-1, #fff);
		font-size: 0.85rem;
	}

	.inspector h3 {
		margin: 0 0 0.2rem;
		font-size: 1rem;
	}

	.inspector h4 {
		margin: 0.75rem 0 0.25rem;
		font-size: 0.78rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-muted, #5f6b7a);
	}

	.node-type {
		margin: 0;
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--accent, #3b82f6);
		font-weight: 700;
	}

	.goal {
		margin: 0.35rem 0 0;
		color: var(--text-muted, #5f6b7a);
	}

	.inspector pre {
		margin: 0;
		padding: 0.6rem;
		border-radius: 6px;
		background: var(--surface-2, #eef1f5);
		overflow: auto;
		font-size: 0.78rem;
		white-space: pre-wrap;
	}

	.inspector ul {
		margin: 0;
		padding-left: 1.1rem;
	}

	.action-log {
		border: 1px solid var(--border, #d3d9e1);
		border-radius: 10px;
		background: var(--surface-1, #fff);
		padding: 0.75rem 1rem;
	}

	.action-log summary {
		cursor: pointer;
		font-size: 0.85rem;
		font-weight: 600;
	}

	.action-log ol {
		margin: 0.6rem 0 0;
		padding-left: 1.2rem;
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}

	.log-time {
		color: var(--text-muted, #5f6b7a);
		font-size: 0.75rem;
		margin-right: 0.5rem;
	}

	.log-kind {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.78rem;
		color: var(--accent, #3b82f6);
	}

	.btn {
		padding: 0.5rem 0.9rem;
		border-radius: 8px;
		border: 1px solid var(--border, #d3d9e1);
		background: var(--surface-1, #fff);
		color: var(--text, #1a2230);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		text-decoration: none;
	}

	.btn-primary {
		background: var(--accent, #3b82f6);
		border-color: var(--accent, #3b82f6);
		color: #fff;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.82em;
	}
</style>
