<script lang="ts">
	import type { EngineAction, FlowExecutionState } from '$lib/types';

	/** Current execution state (null before a flow is started/loaded). */
	export let state: FlowExecutionState | null = null;
	/** Last engine action, rendered verbatim. */
	export let action: EngineAction | null = null;
	export let busy = false;
	export let awaitingInput = false;
	export let terminal = false;
	/** Step id used by Complete step (falls back to the current node). */
	export let currentStep = '';

	export let onAdvance: () => void;
	export let onComplete: (output: string) => void;
	export let onProvideInput: (input: string) => void;
	export let onReject: (reason: string) => void;

	let stepOutput = '';
	let inputText = '';
	let rejectReason = '';

	$: hasFlow = state !== null;
	$: canAdvance = hasFlow && !busy && !terminal && !awaitingInput;
	$: canComplete = hasFlow && !busy && !terminal && currentStep.length > 0;
	$: canReject = hasFlow && !busy && !terminal;

	function verbatim(engineAction: EngineAction | null): string {
		if (!engineAction) return '// no action yet — press Advance';
		try {
			return JSON.stringify(engineAction.raw ?? {}, null, 2);
		} catch {
			return String(engineAction.raw);
		}
	}

	function statusLabel(status: string): string {
		return status.replace(/_/g, ' ');
	}
</script>

<section class="controls" aria-label="Flow execution controls">
	<div class="controls-head">
		{#if state}
			<span class="status status-{state.status}">{statusLabel(state.status)}</span>
			{#if state.current_node_id}
				<span class="muted">current node <code>{state.current_node_id}</code></span>
			{/if}
			{#if awaitingInput}
				<span class="chip chip-warn">awaiting input</span>
			{:else if terminal}
				<span class="chip">flow finished</span>
			{/if}
		{:else}
			<span class="muted">No flow loaded</span>
		{/if}
	</div>

	<div class="actions">
		<button
			type="button"
			class="btn btn-primary"
			on:click={onAdvance}
			disabled={!canAdvance}
		>
			{busy ? 'Working…' : 'Advance'}
		</button>
		{#if awaitingInput}
			<span class="hint">Advance is disabled while the flow awaits human input.</span>
		{/if}
	</div>

	<div class="grid">
		<div class="panel">
			<label for="complete-output">Complete step</label>
			<p class="panel-hint">
				{#if currentStep}step <code>{currentStep}</code>{:else}no active step{/if}
			</p>
			<textarea
				id="complete-output"
				rows="3"
				placeholder="Step output…"
				bind:value={stepOutput}
				disabled={!canComplete}
			></textarea>
			<button
				type="button"
				class="btn"
				on:click={() => onComplete(stepOutput)}
				disabled={!canComplete}
			>
				Complete step
			</button>
		</div>

		<div class="panel" class:panel-active={awaitingInput}>
			<label for="provide-input">Provide input</label>
			<p class="panel-hint">
				{#if awaitingInput}resumes the <code>HumanInput</code> node{:else}enabled only in <code>awaiting_input</code>{/if}
			</p>
			<textarea
				id="provide-input"
				rows="3"
				placeholder="Human input…"
				bind:value={inputText}
				disabled={!awaitingInput || busy}
			></textarea>
			<button
				type="button"
				class="btn"
				on:click={() => onProvideInput(inputText)}
				disabled={!awaitingInput || busy}
			>
				Provide input
			</button>
		</div>

		<div class="panel panel-danger">
			<label for="reject-reason">Reject</label>
			<p class="panel-hint">applies the template's reject chain, when configured</p>
			<textarea
				id="reject-reason"
				rows="3"
				placeholder="Reason (optional)…"
				bind:value={rejectReason}
				disabled={!canReject}
			></textarea>
			<button
				type="button"
				class="btn btn-danger"
				on:click={() => onReject(rejectReason)}
				disabled={!canReject}
			>
				Reject flow
			</button>
		</div>
	</div>

	<div class="action-panel">
		<div class="action-head">
			<span>Engine action (verbatim)</span>
			{#if action}
				<code class="action-kind">{action.kind}</code>
			{/if}
		</div>
		{#if action?.message}
			<p class="action-message">{action.message}</p>
		{/if}
		<pre class="action-json">{verbatim(action)}</pre>
	</div>
</section>

<style>
	.controls {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}

	.controls-head {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		flex-wrap: wrap;
	}

	.status {
		text-transform: uppercase;
		letter-spacing: 0.06em;
		font-size: 0.72rem;
		font-weight: 700;
		padding: 0.25rem 0.55rem;
		border-radius: 999px;
		background: var(--surface-3, #253140);
		color: var(--text, #e7edf5);
	}

	.status-running {
		background: rgba(59, 130, 246, 0.18);
		color: #3b82f6;
	}

	.status-awaiting_input {
		background: rgba(249, 115, 22, 0.18);
		color: #f97316;
	}

	.status-completed {
		background: rgba(34, 197, 94, 0.18);
		color: #22c55e;
	}

	.status-failed,
	.status-rejected {
		background: rgba(239, 68, 68, 0.18);
		color: #ef4444;
	}

	.chip {
		font-size: 0.72rem;
		padding: 0.2rem 0.5rem;
		border-radius: 999px;
		border: 1px solid var(--border, #2c3948);
		color: var(--text-muted, #93a1b3);
	}

	.chip-warn {
		border-color: rgba(249, 115, 22, 0.5);
		color: #f97316;
	}

	.muted {
		color: var(--text-muted, #93a1b3);
		font-size: 0.85rem;
	}

	.hint {
		color: var(--text-muted, #93a1b3);
		font-size: 0.8rem;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: 0.85rem;
	}

	.panel {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
		padding: 0.85rem;
		background: var(--surface-1, #151c25);
		border: 1px solid var(--border, #2c3948);
		border-radius: 10px;
	}

	.panel-active {
		border-color: rgba(249, 115, 22, 0.6);
		box-shadow: 0 0 0 1px rgba(249, 115, 22, 0.25);
	}

	.panel-danger {
		border-color: color-mix(in srgb, #ef4444 35%, var(--border, #2c3948));
	}

	.panel label {
		font-weight: 600;
		font-size: 0.85rem;
	}

	.panel-hint {
		margin: 0;
		font-size: 0.75rem;
		color: var(--text-muted, #93a1b3);
	}

	textarea {
		width: 100%;
		resize: vertical;
		font-family: inherit;
		font-size: 0.85rem;
		padding: 0.5rem;
		border-radius: 6px;
		border: 1px solid var(--border, #2c3948);
		background: var(--surface-2, #1c2530);
		color: var(--text, #e7edf5);
		box-sizing: border-box;
	}

	textarea:disabled {
		opacity: 0.55;
	}

	.btn {
		align-self: flex-start;
		padding: 0.45rem 0.9rem;
		border-radius: 7px;
		border: 1px solid var(--border, #2c3948);
		background: var(--surface-2, #1c2530);
		color: var(--text, #e7edf5);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}

	.btn:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}

	.btn-primary {
		background: var(--accent, #3b82f6);
		border-color: var(--accent, #3b82f6);
		color: #fff;
	}

	.btn-danger {
		color: #ef4444;
		border-color: color-mix(in srgb, #ef4444 45%, var(--border, #2c3948));
	}

	.action-panel {
		border: 1px solid var(--border, #2c3948);
		border-radius: 10px;
		background: var(--surface-1, #151c25);
		overflow: hidden;
	}

	.action-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.5rem 0.75rem;
		border-bottom: 1px solid var(--border, #2c3948);
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--text-muted, #93a1b3);
	}

	.action-kind {
		font-size: 0.75rem;
		color: var(--accent, #60a5fa);
	}

	.action-message {
		margin: 0;
		padding: 0.5rem 0.75rem 0;
		color: #ef4444;
		font-size: 0.85rem;
	}

	.action-json {
		margin: 0;
		padding: 0.75rem;
		max-height: 260px;
		overflow: auto;
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.78rem;
		line-height: 1.5;
		color: var(--text, #e7edf5);
		white-space: pre;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.82em;
	}
</style>
