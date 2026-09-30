// Svelte store backing the /settings screen.
//
// Holds provider ids and error strings only — never key material. Saving is
// write-only: the value goes straight to the keychain command and the
// configured-id list is refreshed from Rust afterwards.
import { writable } from "svelte/store";
import {
	PROVIDERS,
	deleteProviderKey,
	listConfiguredProviders,
	setProviderKey,
} from "$lib/provider-keys";

/** Ids of providers with a key in the OS keychain. */
export const configuredIds = writable<Set<string>>(new Set());
export const loading = writable(false);
/** Failure to read the configured list (rendered as a page banner). */
export const loadError = writable<string | null>(null);
/** Per-provider failure of a save/remove action (rendered under the row). */
export const actionErrors = writable<Record<string, string | null>>({});
/** Provider whose key was just saved, driving the transient "Saved" note. */
export const lastSavedId = writable<string | null>(null);

function message(error: unknown): string {
	if (error instanceof Error && error.message) return error.message;
	return typeof error === "string" && error ? error : "Something went wrong";
}

function setActionError(id: string, value: string | null): void {
	actionErrors.update((current) => ({ ...current, [id]: value }));
}

/** Re-read which providers have a key configured. */
export async function refreshConfigured(): Promise<void> {
	loading.set(true);
	try {
		const ids = await listConfiguredProviders();
		configuredIds.set(new Set(ids));
		loadError.set(null);
	} catch (error) {
		loadError.set(message(error));
	} finally {
		loading.set(false);
	}
}

/**
 * Store (or replace) a provider key. Returns true on success so the caller
 * can clear the input — the value must not linger in the DOM.
 */
export async function saveKey(id: string, value: string): Promise<boolean> {
	if (!PROVIDERS.some((provider) => provider.id === id)) {
		setActionError(id, `Unknown provider \`${id}\``);
		return false;
	}
	if (!value.trim()) {
		setActionError(id, "Enter a key first, or use Remove to delete it.");
		return false;
	}

	setActionError(id, null);
	try {
		await setProviderKey(id, value);
	} catch (error) {
		setActionError(id, message(error));
		return false;
	}

	configuredIds.update((current) => new Set(current).add(id));
	lastSavedId.set(id);
	return true;
}

/** Remove a provider key. Returns true on success. */
export async function removeKey(id: string): Promise<boolean> {
	setActionError(id, null);
	try {
		await deleteProviderKey(id);
	} catch (error) {
		setActionError(id, message(error));
		return false;
	}

	configuredIds.update((current) => {
		const next = new Set(current);
		next.delete(id);
		return next;
	});
	return true;
}
