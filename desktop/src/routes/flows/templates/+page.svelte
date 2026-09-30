<script lang="ts">
	import { onMount } from "svelte";
	import { templateNodeCount, templateTransitionCount } from "$lib/flow-model";
	import {
		addTransition,
		classifyTemplateError,
		createTemplate,
		deleteTemplate,
		getTemplate,
		listTemplates,
		removeTransition,
		toFlowTemplateError,
		updateTemplate,
	} from "$lib/flow-templates-api";
	import {
		emptyNodeDraft,
		emptyTemplateDraft,
		emptyTransitionDraft,
		templateDraftFromTemplate,
		templateInputFromDraft,
		type TemplateDraft,
		type TransitionDraft,
	} from "$lib/template-draft";
	import type { FlowTemplate } from "$lib/types";

	// Authoring surface for the engine's flow-template registry. The list is the
	// raw registry (no seeded fallback): every card here can be PATCHed or
	// DELETEd, so a slug that only exists in the client catalogue would 404.
	let templates: FlowTemplate[] = [];
	let listLoading = true;
	let listError: string | null = null;

	let draft: TemplateDraft | null = null;
	let busy = false;
	/** Rejected save / delete, rendered next to the form. */
	let formError: string | null = null;
	/** Rejected transition sub-resource call. */
	let transitionError: string | null = null;
	let deleteConfirm = false;
	let newTransition: TransitionDraft = emptyTransitionDraft();

	onMount(() => {
		void reloadTemplates();
	});

	async function reloadTemplates(): Promise<void> {
		listLoading = true;
		listError = null;
		try {
			templates = await listTemplates();
		} catch (error) {
			listError = toFlowTemplateError(error).message;
		} finally {
			listLoading = false;
		}
	}

	/** Re-read the template being edited so the form reflects what persisted. */
	async function refreshEditor(): Promise<void> {
		const id = draft?.id;
		if (!id) return;
		try {
			draft = templateDraftFromTemplate(await getTemplate(id));
		} catch (error) {
			// The template may have been removed elsewhere; the list reload below
			// is authoritative either way.
			transitionError = toFlowTemplateError(error).message;
		}
	}

	function openTemplate(template: FlowTemplate): void {
		draft = templateDraftFromTemplate(template);
		formError = null;
		transitionError = null;
		deleteConfirm = false;
		newTransition = emptyTransitionDraft();
	}

	function startCreate(): void {
		draft = emptyTemplateDraft();
		formError = null;
		transitionError = null;
		deleteConfirm = false;
	}

	function closeEditor(): void {
		draft = null;
		formError = null;
		transitionError = null;
		deleteConfirm = false;
	}

	function addNodeRow(): void {
		if (!draft) return;
		draft.nodes = [
			...draft.nodes,
			emptyNodeDraft(`node_${draft.nodes.length + 1}`),
		];
	}

	function removeNodeRow(index: number): void {
		if (!draft) return;
		draft.nodes = draft.nodes.filter((_, at) => at !== index);
	}

	function addTransitionRow(): void {
		if (!draft) return;
		draft.transitions = [...draft.transitions, emptyTransitionDraft()];
	}

	function removeTransitionRow(index: number): void {
		if (!draft) return;
		draft.transitions = draft.transitions.filter((_, at) => at !== index);
	}

	async function saveTemplate(): Promise<void> {
		if (!draft) return;
		busy = true;
		formError = null;
		const editingId = draft.id;
		try {
			const input = templateInputFromDraft(draft);
			const saved = editingId
				? await updateTemplate(editingId, input)
				: await createTemplate(input);
			await reloadTemplates();
			openTemplate(saved);
		} catch (error) {
			const failure = toFlowTemplateError(error);
			formError = failure.message;
			// A network failure leaves the outcome unknown: resync the list so a
			// save that did land is not shown as missing.
			if (classifyTemplateError(failure) === "network") await reloadTemplates();
		} finally {
			busy = false;
		}
	}

	async function removeTemplate(): Promise<void> {
		if (!draft?.id) return;
		busy = true;
		formError = null;
		try {
			await deleteTemplate(draft.id);
			closeEditor();
			await reloadTemplates();
		} catch (error) {
			// 409 "in use by N instance(s)": keep the editor (and its draft) open so
			// the user does not lose the template they were working on.
			formError = toFlowTemplateError(error).message;
		} finally {
			busy = false;
		}
	}

	async function submitTransition(): Promise<void> {
		const templateId = draft?.id;
		if (!templateId) return;
		busy = true;
		transitionError = null;
		try {
			await addTransition(templateId, {
				id: newTransition.id.trim(),
				from_id: newTransition.fromId.trim(),
				to_id: newTransition.toId.trim(),
				condition: newTransition.condition.trim() || null,
				label: newTransition.label.trim() || null,
			});
			newTransition = emptyTransitionDraft();
			await refreshEditor();
		} catch (error) {
			const failure = toFlowTemplateError(error);
			transitionError = failure.message;
			// 400/409 proved nothing was persisted; only an unknown outcome needs
			// a resync from the engine.
			if (classifyTemplateError(failure) === "network") await refreshEditor();
		} finally {
			busy = false;
		}
	}

	async function deleteTransition(transitionId: string): Promise<void> {
		const templateId = draft?.id;
		if (!templateId) return;
		busy = true;
		transitionError = null;
		try {
			await removeTransition(templateId, transitionId);
			await refreshEditor();
		} catch (error) {
			transitionError = toFlowTemplateError(error).message;
		} finally {
			busy = false;
		}
	}

</script>

<svelte:head><title>Templates · Facet</title></svelte:head>

<section class="authoring">
	<nav class="breadcrumbs">
		<a href="/flows">Flows</a>
		<span aria-hidden="true">/</span>
		<span>Templates</span>
	</nav>

	<header class="page-head">
		<div>
			<h1>Flow templates</h1>
			<p class="subtitle">
				Browse the engine registry with each graph's node and transition shape,
				author a new template, or edit, re-validate and delete an existing one.
			</p>
		</div>
		<button type="button" class="btn btn-primary" on:click={startCreate}>
			New template
		</button>
	</header>

	{#if listError}
		<p class="banner banner-error" role="alert">{listError}</p>
	{/if}

	{#if draft}
		<section class="editor">
			<header class="editor-head">
				<div>
					<h2>{draft.id ? `Edit ${draft.id}` : "New template"}</h2>
					<p class="subtitle">
						{#if draft.id}
							Save sends <code>PATCH /api/v1/flow-templates/{draft.id}</code>; the
							whole graph is re-validated by the engine.
						{:else}
							Save sends <code>POST /api/v1/flow-templates</code>; a rejected graph
							answers 400 with the first validator failure.
						{/if}
					</p>
				</div>
				<button type="button" class="btn" on:click={closeEditor}>Close</button>
			</header>

			{#if formError}
				<p class="banner banner-error" role="alert">{formError}</p>
			{/if}

			<form on:submit|preventDefault={saveTemplate}>
				<div class="meta-grid">
					<div class="field">
						<label for="template-name">Name</label>
						<input id="template-name" type="text" bind:value={draft.name} required />
					</div>

					<div class="field">
						<label for="template-initial">Initial node</label>
						<select id="template-initial" bind:value={draft.initialNodeId}>
							<option value="">Select a node…</option>
							{#each draft.nodes as node, index (index)}
								<option value={node.id}>{node.id || "(unnamed node)"}</option>
							{/each}
						</select>
					</div>

					<div class="field">
						<label for="template-on-done">On done template</label>
						<select id="template-on-done" bind:value={draft.onDoneTemplateId}>
							<option value="">none</option>
							{#each templates as template (template.id)}
								<option value={template.id}>{template.name}</option>
							{/each}
						</select>
					</div>

					<div class="field">
						<label for="template-on-reject">On reject template</label>
						<select id="template-on-reject" bind:value={draft.onRejectTemplateId}>
							<option value="">none</option>
							{#each templates as template (template.id)}
								<option value={template.id}>{template.name}</option>
							{/each}
						</select>
					</div>

					<div class="field field-wide">
						<label for="template-description">Description</label>
						<textarea
							id="template-description"
							rows="2"
							bind:value={draft.description}
						></textarea>
					</div>
				</div>

				<fieldset>
					<legend>Nodes ({draft.nodes.length})</legend>
					<p class="hint">
						<code>step</code> nodes need a prompt; <code>sequence</code>,
						<code>loop</code> and <code>parallel</code> nodes need at least one child;
						<code>branch</code> nodes route through their rules.
					</p>

					{#each draft.nodes as node, index (index)}
						<div class="row">
							<div class="row-grid">
								<div class="field">
									<label for={`node-${index}-id`}>Node id</label>
									<input id={`node-${index}-id`} type="text" bind:value={node.id} />
								</div>
								<div class="field">
									<label for={`node-${index}-name`}>Name</label>
									<input id={`node-${index}-name`} type="text" bind:value={node.name} />
								</div>
								<div class="field">
									<label for={`node-${index}-type`}>Type</label>
									<select id={`node-${index}-type`} bind:value={node.node_type}>
										<option value="step">step</option>
										<option value="sequence">sequence</option>
										<option value="branch">branch</option>
										<option value="loop">loop</option>
										<option value="parallel">parallel</option>
										<option value="human_input">human_input</option>
									</select>
								</div>
								<div class="field">
									<label for={`node-${index}-children`}>Children (comma separated)</label>
									<input
										id={`node-${index}-children`}
										type="text"
										bind:value={node.childIds}
									/>
								</div>
							</div>

							<div class="field">
								<label for={`node-${index}-goal`}>Goal</label>
								<input id={`node-${index}-goal`} type="text" bind:value={node.goal} />
							</div>

							<div class="field">
								<label for={`node-${index}-prompt`}>Prompt (required for step)</label>
								<textarea id={`node-${index}-prompt`} rows="2" bind:value={node.prompt}></textarea>
							</div>

							<div class="field">
								<label for={`node-${index}-rules`}>
									Branch rules — one <code>condition =&gt; target_id</code> per line
								</label>
								<textarea id={`node-${index}-rules`} rows="2" bind:value={node.branchRules}></textarea>
							</div>

							{#if node.node_type === "loop"}
								<div class="row-grid">
									<div class="field">
										<label for={`node-${index}-loop-max`}>Loop max iterations</label>
										<input
											id={`node-${index}-loop-max`}
											type="number"
											min="1"
											bind:value={node.loopMaxIterations}
										/>
									</div>
									<div class="field">
										<label for={`node-${index}-loop-exit`}>Loop exit condition</label>
										<input
											id={`node-${index}-loop-exit`}
											type="text"
											bind:value={node.loopExitCondition}
										/>
									</div>
									<div class="field">
										<label for={`node-${index}-schema`}>Output schema</label>
										<input
											id={`node-${index}-schema`}
											type="text"
											bind:value={node.outputSchema}
										/>
									</div>
								</div>
							{/if}

							<button
								type="button"
								class="btn btn-small"
								on:click={() => removeNodeRow(index)}
							>
								Remove node
							</button>
						</div>
					{/each}

					<button type="button" class="btn" on:click={addNodeRow}>Add node</button>
				</fieldset>

				{#if draft.id}
					<section class="transitions">
						<h3>Transitions</h3>
						<p class="hint">
							Each change calls
							<code>/api/v1/flow-templates/{draft.id}/transitions</code>
							and re-validates the graph before persisting.
						</p>

						{#if transitionError}
							<p class="banner banner-error" role="alert">{transitionError}</p>
						{/if}

						{#if draft.transitions.length === 0}
							<p class="hint">No transitions stored.</p>
						{:else}
							<ul class="edges">
								{#each draft.transitions as transition (transition.id)}
									<li>
										<code>{transition.fromId}</code>
										<span aria-hidden="true">→</span>
										<code>{transition.toId}</code>
										{#if transition.condition}<em>{transition.condition}</em>{/if}
										{#if transition.label}<span class="badge">{transition.label}</span>{/if}
										<button
											type="button"
											class="btn btn-small"
											disabled={busy}
											on:click={() => deleteTransition(transition.id)}
										>
											Remove
										</button>
									</li>
								{/each}
							</ul>
						{/if}

						<div class="transition-form">
							<div class="field">
								<label for="transition-id">Transition id</label>
								<input id="transition-id" type="text" bind:value={newTransition.id} />
							</div>
							<div class="field">
								<label for="transition-from">From</label>
								<input id="transition-from" type="text" bind:value={newTransition.fromId} />
							</div>
							<div class="field">
								<label for="transition-to">To</label>
								<input id="transition-to" type="text" bind:value={newTransition.toId} />
							</div>
							<div class="field">
								<label for="transition-condition">Condition</label>
								<input
									id="transition-condition"
									type="text"
									bind:value={newTransition.condition}
								/>
							</div>
							<div class="field">
								<label for="transition-label">Label</label>
								<input id="transition-label" type="text" bind:value={newTransition.label} />
							</div>
							<button
								type="button"
								class="btn"
								disabled={busy}
								on:click={submitTransition}
							>
								Add transition
							</button>
						</div>
					</section>
				{:else}
					<fieldset>
						<legend>Transitions ({draft.transitions.length})</legend>
						<p class="hint">
							Sent with the create body. A self-transition is always invalid; a cycle
							is only legal through a <code>branch</code> or <code>loop</code> node.
						</p>

						{#each draft.transitions as transition, index (index)}
							<div class="transition-form">
								<div class="field">
									<label for={`new-transition-${index}-id`}>Transition id</label>
									<input id={`new-transition-${index}-id`} type="text" bind:value={transition.id} />
								</div>
								<div class="field">
									<label for={`new-transition-${index}-from`}>From</label>
									<input id={`new-transition-${index}-from`} type="text" bind:value={transition.fromId} />
								</div>
								<div class="field">
									<label for={`new-transition-${index}-to`}>To</label>
									<input id={`new-transition-${index}-to`} type="text" bind:value={transition.toId} />
								</div>
								<div class="field">
									<label for={`new-transition-${index}-condition`}>Condition</label>
									<input
										id={`new-transition-${index}-condition`}
										type="text"
										bind:value={transition.condition}
									/>
								</div>
								<button
									type="button"
									class="btn btn-small"
									on:click={() => removeTransitionRow(index)}
								>
									Remove
								</button>
							</div>
						{/each}

						<button type="button" class="btn" on:click={addTransitionRow}>
							Add transition
						</button>
					</fieldset>
				{/if}

				<div class="actions">
					<button type="submit" class="btn btn-primary" disabled={busy}>
						{busy ? "Working…" : draft.id ? "Save template" : "Create template"}
					</button>
					{#if draft.id}
						{#if deleteConfirm}
							<span class="confirm">
								Delete <code>{draft.id}</code> permanently?
								<button
									type="button"
									class="btn btn-danger"
									disabled={busy}
									on:click={removeTemplate}
								>
									Yes, delete
								</button>
								<button type="button" class="btn" on:click={() => (deleteConfirm = false)}>
									Keep
								</button>
							</span>
						{:else}
							<button type="button" class="btn btn-danger" on:click={() => (deleteConfirm = true)}>
								Delete template
							</button>
						{/if}
					{/if}
				</div>
			</form>
		</section>
	{/if}

	{#if listLoading && templates.length === 0}
		<p class="state">Loading templates…</p>
	{:else if templates.length === 0}
		<p class="state">No templates in the engine registry yet.</p>
	{:else}
		<ul class="cards">
			{#each templates as template (template.id)}
				<li class="card">
					<header class="card-head">
						<div>
							<code class="slug">{template.id}</code>
							<strong>{template.name}</strong>
							<p class="desc">{template.description}</p>
						</div>
						<button type="button" class="btn" on:click={() => openTemplate(template)}>
							Edit
						</button>
					</header>

					<span class="meta">
						{templateNodeCount(template)} nodes · {templateTransitionCount(template)} edges
						{#if template.on_reject_template_id}
							· rejects into <code>{template.on_reject_template_id}</code>
						{/if}
					</span>

					<details>
						<summary>Shape</summary>
						<ul class="shape">
							{#each template.nodes as node (node.id)}
								<li>
									<code>{node.id}</code>
									<span class="badge">{node.node_type}</span>
									<span class="node-name">{node.name}</span>
									{#if node.id === template.initial_node_id}
										<span class="badge badge-accent">initial</span>
									{/if}
								</li>
							{/each}
						</ul>
						{#if template.transitions.length > 0}
							<ul class="edges">
								{#each template.transitions as transition (transition.id)}
									<li>
										<code>{transition.from_id}</code>
										<span aria-hidden="true">→</span>
										<code>{transition.to_id}</code>
										{#if transition.condition}<em>{transition.condition}</em>{/if}
										{#if transition.label}<span class="badge">{transition.label}</span>{/if}
									</li>
								{/each}
							</ul>
						{/if}
					</details>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.authoring {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
		max-width: 960px;
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

	.page-head,
	.editor-head,
	.card-head {
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
		font-size: 1.2rem;
	}

	h3 {
		margin: 0 0 0.35rem;
		font-size: 1rem;
	}

	.subtitle,
	.hint {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.85rem;
	}

	.editor,
	.card {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		padding: 1rem 1.1rem;
		border: 1px solid var(--border);
		border-radius: 10px;
		background: var(--surface-1);
	}

	fieldset {
		margin: 0;
		padding: 0.75rem 0.9rem 0.9rem;
		border: 1px solid var(--border);
		border-radius: 10px;
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}

	legend {
		padding: 0 0.35rem;
		font-size: 0.85rem;
		font-weight: 700;
	}

	.meta-grid,
	.row-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
		gap: 0.6rem;
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.field-wide {
		grid-column: 1 / -1;
	}

	label {
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--text-muted);
	}

	input,
	select,
	textarea {
		padding: 0.45rem 0.55rem;
		border-radius: 7px;
		border: 1px solid var(--border);
		background: var(--surface-2);
		color: var(--text);
		font-size: 0.85rem;
		font-family: inherit;
	}

	textarea {
		resize: vertical;
	}

	.row {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		padding: 0.65rem;
		border: 1px dashed var(--border);
		border-radius: 8px;
	}

	.transitions {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-top: 0.75rem;
	}

	.transition-form {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
		gap: 0.5rem;
		align-items: end;
	}

	.edges,
	.shape {
		list-style: none;
		margin: 0.5rem 0 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.85rem;
	}

	.edges li,
	.shape li {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
	}

	.node-name {
		color: var(--text-muted);
	}

	.badge {
		font-size: 0.7rem;
		padding: 0.1rem 0.4rem;
		border-radius: 999px;
		border: 1px solid var(--border);
		color: var(--text-muted);
	}

	.badge-accent {
		border-color: var(--accent);
		color: var(--accent);
	}

	.cards {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}

	.slug {
		display: block;
		font-size: 0.78rem;
		font-weight: 700;
		color: var(--accent);
	}

	.desc,
	.meta,
	.state {
		margin: 0.2rem 0 0;
		font-size: 0.82rem;
		color: var(--text-muted);
	}

	.state {
		padding: 1.25rem;
		text-align: center;
	}

	.banner {
		margin: 0;
		padding: 0.6rem 0.85rem;
		border-radius: 8px;
		font-size: 0.85rem;
	}

	.banner-error {
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		flex-wrap: wrap;
		margin-top: 0.85rem;
	}

	.confirm {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.85rem;
		color: var(--text-muted);
	}

	.btn {
		padding: 0.45rem 0.85rem;
		border-radius: 8px;
		border: 1px solid var(--border);
		background: var(--surface-2);
		color: var(--text);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}

	.btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.btn-small {
		align-self: flex-start;
		padding: 0.3rem 0.6rem;
		font-size: 0.78rem;
	}

	.btn-primary {
		background: var(--accent);
		border-color: var(--accent);
		color: #fff;
	}

	.btn-danger {
		border-color: rgba(239, 68, 68, 0.55);
		color: #ef4444;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.82em;
	}
</style>
