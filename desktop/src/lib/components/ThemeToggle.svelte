<script lang="ts">
	import { theme, toggleTheme } from "$lib/theme";

	$: isDark = $theme === "dark";
</script>

<button
	class="theme-toggle"
	type="button"
	on:click={toggleTheme}
	title={isDark ? "Switch to light theme" : "Switch to dark theme"}
	aria-label={isDark ? "Switch to light theme" : "Switch to dark theme"}
>
	{#if isDark}
		<span aria-hidden="true">🌙</span><span class="text">Dark</span>
	{:else}
		<span aria-hidden="true">☀️</span><span class="text">Light</span>
	{/if}
</button>

<style>
	.theme-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		width: 100%;
		padding: 0.45rem 0.6rem;
		border-radius: 8px;
		border: 1px solid var(--border);
		background: var(--surface-2);
		color: var(--text);
		font-size: 0.8rem;
		cursor: pointer;
		transition: background 0.15s ease, border-color 0.15s ease;
	}

	.theme-toggle:hover {
		background: var(--surface-3);
	}

	.text {
		font-weight: 600;
	}
</style>
