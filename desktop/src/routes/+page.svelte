<script lang="ts">
	import { backend } from "$lib/backend";
	import { theme } from "$lib/theme";

	$: status = $backend;
</script>

<section class="overview">
	<header>
		<h1>Overview</h1>
		<p class="subtitle">
			Facet is the desktop client for Crystalline, the embedded AI workflow
			orchestration engine.
		</p>
	</header>

	<div class="cards">
		<article class="card">
			<h2>Connection</h2>
			<dl>
				<dt>Mode</dt>
				<dd>{status.mode === "remote" ? "Remote instance" : "Embedded sidecar"}</dd>
				<dt>State</dt>
				<dd class="state state-{status.state}">{status.state}</dd>
				<dt>Base URL</dt>
				<dd><code>{status.base_url ?? "—"}</code></dd>
				<dt>Version</dt>
				<dd>{status.version ? `v${status.version}` : "—"}</dd>
			</dl>
		</article>

		<article class="card">
			<h2>Appearance</h2>
			<p class="muted">
				Current theme: <strong>{$theme}</strong>. Use the toggle in the sidebar
				to switch between light and dark.
			</p>
		</article>
	</div>

	{#if status.state === "error"}
		<article class="card card-error">
			<h2>Startup error</h2>
			<p>{status.error ?? "Unknown error."}</p>
			<p class="muted">
				Set <code>FACET_URL</code> to point at a remote Crystalline instance, or
				build the local sidecar with <code>scripts/build.sh</code>.
			</p>
		</article>
	{/if}
</section>

<style>
	.overview {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
		max-width: 900px;
	}

	h1 {
		margin: 0 0 0.25rem;
		font-size: 1.5rem;
	}

	.subtitle {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.95rem;
	}

	.cards {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
		gap: 1rem;
	}

	.card {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 1.1rem 1.25rem;
	}

	.card h2 {
		margin: 0 0 0.75rem;
		font-size: 1rem;
	}

	dl {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: 0.4rem 1rem;
		margin: 0;
		font-size: 0.9rem;
	}

	dt {
		color: var(--text-muted);
	}

	dd {
		margin: 0;
		text-align: right;
		word-break: break-all;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.85em;
	}

	.muted {
		color: var(--text-muted);
		font-size: 0.9rem;
	}

	.state {
		font-weight: 600;
		text-transform: capitalize;
	}

	.state-ready {
		color: #22c55e;
	}

	.state-starting {
		color: #f59e0b;
	}

	.state-error {
		color: #ef4444;
	}

	.card-error {
		border-color: rgba(239, 68, 68, 0.4);
	}
</style>
