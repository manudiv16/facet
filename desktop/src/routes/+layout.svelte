<script lang="ts">
	import { onMount } from "svelte";
	import { page } from "$app/stores";
	import { backend, initBackend } from "$lib/backend";
	import StatusIndicator from "$lib/components/StatusIndicator.svelte";
	import ThemeToggle from "$lib/components/ThemeToggle.svelte";
	import "$lib/theme";

	const nav = [
		{ href: "/", label: "Overview", icon: "◈" },
		{ href: "/tasks", label: "Tasks", icon: "✓" },
		{ href: "/flows", label: "Flows", icon: "⌥" },
		{ href: "/executions", label: "Executions", icon: "▶" },
		{ href: "/settings", label: "Settings", icon: "⚙" },
	];

	onMount(() => {
		void initBackend();
	});

	function isActive(href: string, pathname: string): boolean {
		if (href === "/") return pathname === "/" || pathname === "";
		return pathname.startsWith(href);
	}
</script>

<div class="app">
	<aside class="sidebar">
		<div class="brand">
			<span class="brand-mark" aria-hidden="true">◆</span>
			<span class="brand-name">Facet</span>
		</div>

		<nav class="nav" aria-label="Primary">
			{#each nav as item (item.href)}
				<a
					class="nav-item"
					class:active={isActive(item.href, $page.url.pathname)}
					href={item.href}
					aria-current={isActive(item.href, $page.url.pathname) ? "page" : undefined}
				>
					<span class="nav-icon" aria-hidden="true">{item.icon}</span>
					<span>{item.label}</span>
				</a>
			{/each}
		</nav>

		<div class="sidebar-footer">
			<StatusIndicator {backend} />
			<ThemeToggle />
		</div>
	</aside>

	<main class="content">
		{#if $backend.state === "error"}
			<div class="banner" role="alert">
				<strong>Crystalline is unavailable.</strong>
				<span>{$backend.error ?? "The sidecar did not become healthy."}</span>
			</div>
		{:else if $backend.state === "starting"}
			<div class="banner banner-info" role="status">
				<strong>Starting Crystalline…</strong>
				<span>Waiting for the local engine to become healthy.</span>
			</div>
		{/if}

		<slot />
	</main>
</div>

<style>
	:global(:root) {
		--bg: #f6f7f9;
		--surface-1: #ffffff;
		--surface-2: #eef1f5;
		--surface-3: #e2e6ec;
		--border: #d3d9e1;
		--text: #1a2230;
		--text-muted: #5f6b7a;
		--accent: #3b82f6;
		color-scheme: light;
	}

	:global(:root[data-theme="dark"]) {
		--bg: #0f141b;
		--surface-1: #151c25;
		--surface-2: #1c2530;
		--surface-3: #253140;
		--border: #2c3948;
		--text: #e7edf5;
		--text-muted: #93a1b3;
		--accent: #60a5fa;
		color-scheme: dark;
	}

	:global(html),
	:global(body) {
		margin: 0;
		height: 100%;
		background: var(--bg);
		color: var(--text);
		font-family:
			ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica,
			Arial, sans-serif;
	}

	.app {
		display: grid;
		grid-template-columns: 220px 1fr;
		height: 100vh;
		overflow: hidden;
	}

	.sidebar {
		display: flex;
		flex-direction: column;
		background: var(--surface-1);
		border-right: 1px solid var(--border);
		padding: 1rem 0.75rem;
		gap: 1.25rem;
	}

	.brand {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.25rem 0.5rem;
	}

	.brand-mark {
		color: var(--accent);
		font-size: 1.1rem;
	}

	.brand-name {
		font-size: 1.15rem;
		font-weight: 700;
		letter-spacing: 0.01em;
	}

	.nav {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		flex: 1;
	}

	.nav-item {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.55rem 0.65rem;
		border-radius: 8px;
		color: var(--text-muted);
		text-decoration: none;
		font-size: 0.9rem;
		font-weight: 500;
		transition: background 0.15s ease, color 0.15s ease;
	}

	.nav-item:hover {
		background: var(--surface-2);
		color: var(--text);
	}

	.nav-item.active {
		background: color-mix(in srgb, var(--accent) 16%, transparent);
		color: var(--accent);
	}

	.nav-icon {
		width: 1.1rem;
		text-align: center;
	}

	.sidebar-footer {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.content {
		overflow: auto;
		padding: 1.5rem 2rem;
	}

	.banner {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: 0.75rem 1rem;
		margin-bottom: 1.25rem;
		border-radius: 8px;
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
		font-size: 0.9rem;
	}

	.banner-info {
		border-color: color-mix(in srgb, var(--accent) 45%, transparent);
		background: color-mix(in srgb, var(--accent) 10%, transparent);
		color: var(--accent);
	}
</style>
