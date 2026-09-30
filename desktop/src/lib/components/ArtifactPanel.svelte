<script lang="ts">
	// Artifacts panel for the task detail page (facet#9).
	//
	// Lists the task's named JSON artifacts (engine order: logical name),
	// renders one artifact's content on demand, and upserts one by logical name
	// — the engine's PUT is an upsert, so the same form both creates and
	// updates. Deletes go through the page's detail store; failures surface in
	// the `error` banner.
	import { formatTimestamp } from "$lib/tasks-utils";
	import type { Artifact } from "$lib/types";

	export let artifacts: Artifact[] = [];
	export let loading = false;
	export let error: string | null = null;
	export let onSave: (logicalName: string, content: unknown) => Promise<void> =
		async () => {};
	export let onDelete: (logicalName: string) => Promise<void> = async () => {};

	/** Pretty-printed JSON, or the raw value when it is not serialisable. */
	function pretty(value: unknown): string {
		if (value === undefined) return "";
		const text = JSON.stringify(value, null, 2);
		return text === undefined ? String(value) : text;
	}

	let name = "";
	let contentText = "";
	let saveError: string | null = null;
	let saving = false;
	let busyName: string | null = null;
	let viewing: string | null = null;

	function edit(artifact: Artifact) {
		name = artifact.logical_name;
		contentText = pretty(artifact.content);
		saveError = null;
	}

	async function submit() {
		const logicalName = name.trim();
		if (logicalName === "") {
			saveError = "A logical name is required.";
			return;
		}
		let content: unknown = null;
		if (contentText.trim() !== "") {
			try {
				content = JSON.parse(contentText);
			} catch {
				saveError = "Content must be valid JSON.";
				return;
			}
		}

		saving = true;
		saveError = null;
		try {
			await onSave(logicalName, content);
		} catch {
			// The panel error banner carries the server message.
		} finally {
			saving = false;
		}
	}

	async function remove(artifact: Artifact) {
		busyName = artifact.logical_name;
		try {
			await onDelete(artifact.logical_name);
			if (viewing === artifact.logical_name) viewing = null;
			if (name === artifact.logical_name) {
				name = "";
				contentText = "";
			}
		} catch {
			// The panel error banner carries the server message.
		} finally {
			busyName = null;
		}
	}
</script>

<section class="artifacts">
	<header>
		<h2>Artifacts</h2>
		<p class="hint">
			Named JSON values attached to this task — agent output, specs, notes.
			Saving a name again replaces its content.
		</p>
	</header>

	{#if error}
		<div class="error-banner" role="alert">{error}</div>
	{/if}

	{#if loading}
		<p class="muted">Loading artifacts…</p>
	{:else if artifacts.length === 0}
		<p class="muted">
			{error ? "Artifacts could not be loaded." : "No artifacts."}
		</p>
	{:else}
		<ul class="artifact-list">
			{#each artifacts as artifact (artifact.id)}
				<li>
					<div class="artifact-head">
						<span class="name">{artifact.logical_name}</span>
						<span class="muted">updated {formatTimestamp(artifact.updated_at)}</span>
						<span class="spacer"></span>
						<button
							type="button"
							class="link"
							aria-expanded={viewing === artifact.logical_name}
							on:click={() =>
								(viewing =
									viewing === artifact.logical_name
										? null
										: artifact.logical_name)}
						>
							{viewing === artifact.logical_name ? "Hide" : "View"}
						</button>
						<button
							type="button"
							class="link"
							disabled={busyName === artifact.logical_name}
							on:click={() => edit(artifact)}
						>
							Edit
						</button>
						<button
							type="button"
							class="link danger"
							disabled={busyName === artifact.logical_name}
							on:click={() => remove(artifact)}
						>
							Delete
						</button>
					</div>
					{#if viewing === artifact.logical_name}
						<pre class="content">{pretty(artifact.content)}</pre>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	<form class="save" on:submit|preventDefault={submit}>
		<h3>Save an artifact</h3>
		{#if saveError}
			<div class="row-error" role="alert">{saveError}</div>
		{/if}
		<label>
			Logical name
			<input bind:value={name} placeholder="coverage-report" disabled={saving} />
		</label>
		<label>
			Content (JSON)
			<textarea
				bind:value={contentText}
				rows="5"
				placeholder={'{"status": "ok"}'}
				disabled={saving}
			></textarea>
		</label>
		<div class="row-actions">
			<button type="submit" class="primary" disabled={saving}>
				{saving ? "Saving…" : "Save artifact"}
			</button>
		</div>
	</form>
</section>

<style>
	.artifacts {
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 1rem 1.15rem;
	}

	h2 {
		margin: 0;
		font-size: 1rem;
	}

	h3 {
		margin: 0;
		font-size: 0.9rem;
	}

	.hint {
		margin: 0.2rem 0 0;
		color: var(--text-muted);
		font-size: 0.82rem;
	}

	.error-banner,
	.row-error {
		padding: 0.55rem 0.75rem;
		border-radius: 8px;
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
		font-size: 0.85rem;
	}

	.artifact-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.artifact-list > li {
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 0.55rem 0.75rem;
		background: var(--surface-2);
	}

	.artifact-head {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.name {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.85rem;
	}

	.spacer {
		flex: 1;
	}

	.link {
		border: none;
		background: none;
		color: var(--accent);
		font: inherit;
		font-size: 0.8rem;
		cursor: pointer;
		padding: 0.1rem 0.25rem;
	}

	.link.danger {
		color: #ef4444;
	}

	.link:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.content {
		margin: 0.5rem 0 0;
		padding: 0.6rem 0.7rem;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.78rem;
		white-space: pre-wrap;
		overflow-x: auto;
		max-height: 24rem;
	}

	.save {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		border-top: 1px solid var(--border);
		padding-top: 0.85rem;
	}

	label {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 0.78rem;
		color: var(--text-muted);
	}

	input,
	textarea {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.4rem 0.55rem;
		color: var(--text);
		font: inherit;
		font-size: 0.85rem;
		width: 100%;
		box-sizing: border-box;
	}

	textarea {
		resize: vertical;
	}

	.row-actions {
		display: flex;
		gap: 0.5rem;
	}

	.row-actions button {
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text);
		border-radius: 8px;
		padding: 0.4rem 0.7rem;
		font: inherit;
		font-size: 0.82rem;
		cursor: pointer;
	}

	.row-actions button:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.primary {
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
