<script lang="ts">
	import type { Readable } from "svelte/store";
	import type { BackendStatus } from "$lib/backend";

	export let backend: Readable<BackendStatus>;

	$: status = $backend;

	$: label =
		status.state === "ready"
			? status.mode === "remote"
				? "Remote"
				: "Connected"
			: status.state === "error"
				? "Disconnected"
				: "Starting…";

	$: detail =
		status.state === "ready" && status.mode === "embedded" && status.port
			? `:${status.port}${status.version ? ` · v${status.version}` : ""}`
			: status.state === "error"
				? "sidecar unavailable"
				: "";
</script>

<div class="status status-{status.state}" title={status.error ?? ""}>
	<span class="dot" aria-hidden="true"></span>
	<span class="label">{label}</span>
	{#if detail}
		<span class="detail">{detail}</span>
	{/if}
</div>

<style>
	.status {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.8rem;
		padding: 0.35rem 0.6rem;
		border-radius: 999px;
		border: 1px solid var(--border);
		background: var(--surface-2);
		color: var(--text-muted);
		max-width: 100%;
	}

	.dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--text-muted);
		flex: none;
	}

	.status-ready .dot {
		background: #22c55e;
		box-shadow: 0 0 0 3px rgba(34, 197, 94, 0.18);
	}

	.status-starting .dot {
		background: #f59e0b;
		animation: pulse 1.2s ease-in-out infinite;
	}

	.status-error .dot {
		background: #ef4444;
		box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.18);
	}

	.status-error {
		color: #ef4444;
		border-color: rgba(239, 68, 68, 0.4);
	}

	.label {
		font-weight: 600;
		color: var(--text);
	}

	.detail {
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	@keyframes pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.35;
		}
	}
</style>
