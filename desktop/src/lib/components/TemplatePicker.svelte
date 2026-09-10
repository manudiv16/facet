<script lang="ts">
	import { templateNodeCount, templateTransitionCount } from '$lib/flow-model';
	import type { FlowTemplate } from '$lib/types';

	export let templates: FlowTemplate[] = [];
	export let open = false;
	export let loading = false;
	export let error: string | null = null;
	export let usingFallback = false;
	export let onSelect: (template: FlowTemplate) => void;
	export let onClose: () => void;

	let query = '';

	$: filtered = filterTemplates(templates, query);

	function filterTemplates(list: FlowTemplate[], needle: string): FlowTemplate[] {
		const term = needle.trim().toLowerCase();
		if (!term) return list;
		return list.filter((template) =>
			`${template.slug} ${template.name} ${template.description}`
				.toLowerCase()
				.includes(term),
		);
	}

	function choose(template: FlowTemplate) {
		onSelect(template);
	}

	function handleKeydown(event: KeyboardEvent) {
		if (open && event.key === 'Escape') {
			event.preventDefault();
			onClose();
		}
	}
</script>

<svelte:window on:keydown={handleKeydown} />

{#if open}
	<div
		class="backdrop"
		role="presentation"
		on:click={onClose}
		on:keydown={(event) => event.key === 'Escape' && onClose()}
	>
		<div
			class="dialog"
			role="dialog"
			aria-modal="true"
			aria-labelledby="template-picker-title"
			on:click={(event) => event.stopPropagation()}
			on:keydown={(event) => event.stopPropagation()}
		>
			<header class="dialog-head">
				<div>
					<h2 id="template-picker-title">Choose a flow template</h2>
					<p class="subtitle">
						Picked from <code>GET /api/v1/flow-templates</code>
						{#if usingFallback}— showing seeded slugs{/if}
					</p>
				</div>
				<button
					type="button"
					class="close"
					aria-label="Close template picker"
					on:click={onClose}
				>
					✕
				</button>
			</header>

			<input
				class="search"
				type="search"
				placeholder="Filter by slug, name or description…"
				bind:value={query}
				aria-label="Filter templates"
			/>

			{#if loading}
				<p class="state">Loading templates…</p>
			{:else if error}
				<p class="state state-error">{error}</p>
			{:else if filtered.length === 0}
				<p class="state">No templates match “{query}”.</p>
			{:else}
				<ul class="template-list">
					{#each filtered as template (template.slug)}
						<li>
							<button
								type="button"
								class="template"
								on:click={() => choose(template)}
							>
								<span class="template-slug">{template.slug}</span>
								<span class="template-name">{template.name}</span>
								<span class="template-desc">{template.description}</span>
								<span class="template-meta">
									<span class="badge">{templateNodeCount(template)} nodes</span>
									<span class="badge">{templateTransitionCount(template)} edges</span>
									{#if template.on_reject_template_id}
										<span class="badge badge-warn">reject chain</span>
									{/if}
								</span>
							</button>
						</li>
					{/each}
				</ul>
			{/if}
		</div>
	</div>
{/if}

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(8, 12, 18, 0.6);
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 1.5rem;
		z-index: 50;
	}

	.dialog {
		width: min(680px, 100%);
		max-height: 85vh;
		display: flex;
		flex-direction: column;
		background: var(--surface-1, #151c25);
		border: 1px solid var(--border, #2c3948);
		border-radius: 14px;
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
		padding: 1.1rem 1.25rem;
		gap: 0.9rem;
	}

	.dialog-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	h2 {
		margin: 0 0 0.15rem;
		font-size: 1.1rem;
	}

	.subtitle {
		margin: 0;
		color: var(--text-muted, #93a1b3);
		font-size: 0.8rem;
	}

	.close {
		border: none;
		background: transparent;
		color: var(--text-muted, #93a1b3);
		font-size: 1rem;
		cursor: pointer;
		padding: 0.25rem 0.4rem;
		border-radius: 6px;
	}

	.close:hover {
		background: var(--surface-2, #1c2530);
		color: var(--text, #e7edf5);
	}

	.search {
		width: 100%;
		box-sizing: border-box;
		padding: 0.55rem 0.7rem;
		border-radius: 8px;
		border: 1px solid var(--border, #2c3948);
		background: var(--surface-2, #1c2530);
		color: var(--text, #e7edf5);
		font-size: 0.9rem;
	}

	.state {
		margin: 0;
		padding: 1.25rem;
		text-align: center;
		color: var(--text-muted, #93a1b3);
	}

	.state-error {
		color: #ef4444;
	}

	.template-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		overflow: auto;
	}

	.template {
		width: 100%;
		text-align: left;
		display: grid;
		grid-template-columns: 1fr;
		gap: 0.2rem;
		padding: 0.7rem 0.85rem;
		border-radius: 10px;
		border: 1px solid var(--border, #2c3948);
		background: var(--surface-2, #1c2530);
		color: var(--text, #e7edf5);
		cursor: pointer;
	}

	.template:hover {
		border-color: var(--accent, #3b82f6);
		background: color-mix(in srgb, var(--accent, #3b82f6) 10%, var(--surface-2, #1c2530));
	}

	.template-slug {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.8rem;
		font-weight: 700;
		color: var(--accent, #60a5fa);
	}

	.template-name {
		font-size: 0.95rem;
		font-weight: 600;
	}

	.template-desc {
		font-size: 0.82rem;
		color: var(--text-muted, #93a1b3);
	}

	.template-meta {
		display: flex;
		gap: 0.4rem;
		margin-top: 0.25rem;
		flex-wrap: wrap;
	}

	.badge {
		font-size: 0.7rem;
		padding: 0.15rem 0.45rem;
		border-radius: 999px;
		border: 1px solid var(--border, #2c3948);
		color: var(--text-muted, #93a1b3);
	}

	.badge-warn {
		border-color: rgba(249, 115, 22, 0.5);
		color: #f97316;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.82em;
	}
</style>
