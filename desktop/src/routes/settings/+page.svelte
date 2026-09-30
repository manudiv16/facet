<script lang="ts">
	import { onMount } from "svelte";
	import { PROVIDERS } from "$lib/provider-keys";
	import {
		actionErrors,
		configuredIds,
		lastSavedId,
		loadError,
		refreshConfigured,
		removeKey,
		saveKey,
	} from "$stores/settings";

	// Write-only drafts: a key value lives here only until the save resolves,
	// then the field is cleared so the secret never lingers in the DOM.
	let drafts: Record<string, string> = {};
	let busyId: string | null = null;

	onMount(() => {
		void refreshConfigured();
	});

	async function handleSave(id: string) {
		busyId = id;
		try {
			if (await saveKey(id, drafts[id] ?? "")) {
				drafts = { ...drafts, [id]: "" };
			}
		} finally {
			busyId = null;
		}
	}

	async function handleRemove(id: string) {
		busyId = id;
		try {
			await removeKey(id);
		} finally {
			busyId = null;
		}
	}
</script>

<svelte:head><title>Settings · Facet</title></svelte:head>

<section class="settings">
	<header class="page-head">
		<h1>Settings</h1>
	</header>

	<p class="lede">
		Provider API keys are stored in the OS keychain (macOS Keychain, Windows
		Credential Manager, or the Linux Secret Service) — never in config files
		or the app bundle. They are forwarded to the embedded Crystalline engine
		when it starts; a remote instance (<code>FACET_URL</code>) never receives
		them.
	</p>

	{#if $loadError}
		<p class="banner banner-error" role="alert">{$loadError}</p>
	{/if}

	<div class="providers">
		{#each PROVIDERS as provider (provider.id)}
			{@const isConfigured = $configuredIds.has(provider.id)}
			<section class="provider-row">
				<div class="provider-info">
					<span class="provider-name">{provider.label}</span>
					<code class="env-var">{provider.envVar}</code>
					<span
						class="badge"
						class:configured={isConfigured}
						aria-label={isConfigured ? "Key configured" : "No key configured"}
					>
						{isConfigured ? "Configured" : "Not configured"}
					</span>
				</div>

				<form
					class="provider-actions"
					on:submit|preventDefault={() => handleSave(provider.id)}
				>
					<input
						type="password"
						bind:value={drafts[provider.id]}
						placeholder={isConfigured
							? "Enter a new key to replace the saved one"
							: provider.placeholder}
						aria-label="{provider.label} API key"
						autocomplete="off"
						spellcheck="false"
						disabled={busyId === provider.id}
					/>
					<button
						type="submit"
						class="primary"
						disabled={busyId === provider.id || !(drafts[provider.id] ?? "").trim()}
					>
						{isConfigured ? "Update" : "Save"}
					</button>
					{#if isConfigured}
						<button
							type="button"
							class="danger"
							disabled={busyId === provider.id}
							on:click={() => handleRemove(provider.id)}
						>
							Remove
						</button>
					{/if}
					<a
						class="keys-link"
						href={provider.keysUrl}
						target="_blank"
						rel="noreferrer">Get a key ↗</a
					>
				</form>

				{#if $actionErrors[provider.id]}
					<p class="field-error" role="alert">{$actionErrors[provider.id]}</p>
				{:else if $lastSavedId === provider.id}
					<p class="saved-note">Saved to the OS keychain.</p>
				{/if}
			</section>
		{/each}
	</div>
</section>

<style>
	.settings {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-width: 760px;
	}

	.page-head h1 {
		margin: 0;
		font-size: 1.5rem;
	}

	.lede {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.9rem;
		line-height: 1.5;
	}

	.lede code {
		font-size: 0.85em;
	}

	.banner-error {
		margin: 0;
		padding: 0.65rem 0.85rem;
		border-radius: 8px;
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
		font-size: 0.875rem;
	}

	.providers {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}

	.provider-row {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		padding: 0.85rem 1rem;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 10px;
	}

	.provider-info {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}

	.provider-name {
		font-weight: 600;
		font-size: 0.95rem;
	}

	.env-var {
		color: var(--text-muted);
		font-size: 0.78rem;
		background: var(--surface-2);
		border-radius: 4px;
		padding: 0.1rem 0.35rem;
	}

	.badge {
		margin-left: auto;
		font-size: 0.75rem;
		font-weight: 600;
		padding: 0.15rem 0.55rem;
		border-radius: 999px;
		border: 1px solid var(--border);
		color: var(--text-muted);
		background: var(--surface-2);
	}

	.badge.configured {
		color: #16a34a;
		border-color: rgba(22, 163, 74, 0.4);
		background: rgba(22, 163, 74, 0.1);
	}

	.provider-actions {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.provider-actions input {
		flex: 1;
		min-width: 0;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.5rem 0.7rem;
		color: var(--text);
		font: inherit;
		font-size: 0.9rem;
	}

	.provider-actions input:focus {
		outline: 2px solid color-mix(in srgb, var(--accent) 55%, transparent);
		outline-offset: 1px;
		border-color: var(--accent);
	}

	button {
		font: inherit;
		font-weight: 600;
		border-radius: 8px;
		padding: 0.5rem 1rem;
		cursor: pointer;
		border: none;
	}

	button:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	button.primary {
		background: var(--accent);
		color: white;
	}

	button.danger {
		background: transparent;
		color: #ef4444;
		border: 1px solid rgba(239, 68, 68, 0.4);
	}

	.keys-link {
		color: var(--accent);
		font-size: 0.82rem;
		text-decoration: none;
		white-space: nowrap;
	}

	.keys-link:hover {
		text-decoration: underline;
	}

	.field-error {
		margin: 0;
		color: #ef4444;
		font-size: 0.8rem;
	}

	.saved-note {
		margin: 0;
		color: #16a34a;
		font-size: 0.8rem;
	}
</style>
