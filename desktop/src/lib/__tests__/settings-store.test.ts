// Store tests for `$stores/settings`: keychain-backed provider keys.
//
// The Tauri bridge (`$lib/provider-keys`) is fully mocked so these tests
// verify the store contract: save/remove update the configured-id set, errors
// surface per provider with the backend message, and no key value is ever
// retained in any store after a save.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { get } from "svelte/store";
import type * as ProviderKeys from "$lib/provider-keys";

const apiMocks = vi.hoisted(() => ({
	listConfiguredProviders: vi.fn(),
	setProviderKey: vi.fn(),
	deleteProviderKey: vi.fn(),
}));

vi.mock("$lib/provider-keys", async () => {
	const actual = await vi.importActual<typeof ProviderKeys>(
		"$lib/provider-keys",
	);
	return {
		...actual,
		listConfiguredProviders: apiMocks.listConfiguredProviders,
		setProviderKey: apiMocks.setProviderKey,
		deleteProviderKey: apiMocks.deleteProviderKey,
	};
});

import {
	actionErrors,
	configuredIds,
	lastSavedId,
	loadError,
	loading,
	refreshConfigured,
	removeKey,
	saveKey,
} from "$stores/settings";

const FAKE_KEY = "facet-fake-ui-key-0001";

beforeEach(() => {
	vi.resetAllMocks();
	configuredIds.set(new Set());
	loading.set(false);
	loadError.set(null);
	actionErrors.set({});
	lastSavedId.set(null);
});

describe("refreshConfigured", () => {
	it("populates the configured-id set from the backend", async () => {
		apiMocks.listConfiguredProviders.mockResolvedValue(["anthropic", "groq"]);

		await refreshConfigured();

		expect(get(configuredIds)).toEqual(new Set(["anthropic", "groq"]));
		expect(get(loadError)).toBeNull();
		expect(get(loading)).toBe(false);
	});

	it("surfaces the backend message when the read fails", async () => {
		apiMocks.listConfiguredProviders.mockRejectedValue(
			new Error("keychain unavailable"),
		);

		await refreshConfigured();

		expect(get(loadError)).toBe("keychain unavailable");
		expect(get(configuredIds)).toEqual(new Set());
	});
});

describe("saveKey", () => {
	it("stores the key and marks the provider configured", async () => {
		apiMocks.setProviderKey.mockResolvedValue(undefined);

		const ok = await saveKey("anthropic", FAKE_KEY);

		expect(ok).toBe(true);
		expect(apiMocks.setProviderKey).toHaveBeenCalledWith(
			"anthropic",
			FAKE_KEY,
		);
		expect(get(configuredIds).has("anthropic")).toBe(true);
		expect(get(lastSavedId)).toBe("anthropic");
		expect(get(actionErrors)["anthropic"]).toBeNull();
	});

	it("surfaces the backend message and keeps state on failure", async () => {
		apiMocks.setProviderKey.mockRejectedValue(
			new Error("keychain write failed: denied"),
		);

		const ok = await saveKey("openai", FAKE_KEY);

		expect(ok).toBe(false);
		expect(get(actionErrors)["openai"]).toBe("keychain write failed: denied");
		expect(get(configuredIds).has("openai")).toBe(false);
	});

	it("rejects an unknown provider without touching the keychain", async () => {
		const ok = await saveKey("not-a-provider", FAKE_KEY);

		expect(ok).toBe(false);
		expect(apiMocks.setProviderKey).not.toHaveBeenCalled();
		expect(get(actionErrors)["not-a-provider"]).toContain("Unknown provider");
	});

	it("rejects a blank key without touching the keychain", async () => {
		const ok = await saveKey("anthropic", "   ");

		expect(ok).toBe(false);
		expect(apiMocks.setProviderKey).not.toHaveBeenCalled();
		expect(get(actionErrors)["anthropic"]).toContain("Enter a key");
	});

	it("retains no key material in any store after a save", async () => {
		apiMocks.setProviderKey.mockResolvedValue(undefined);

		await saveKey("anthropic", FAKE_KEY);

		const snapshot = [
			get(configuredIds),
			get(actionErrors),
			get(lastSavedId),
			get(loadError),
		];
		expect(JSON.stringify(snapshot)).not.toContain(FAKE_KEY);
	});
});

describe("removeKey", () => {
	it("deletes the key and unmarks the provider", async () => {
		configuredIds.set(new Set(["anthropic"]));
		apiMocks.deleteProviderKey.mockResolvedValue(undefined);

		const ok = await removeKey("anthropic");

		expect(ok).toBe(true);
		expect(apiMocks.deleteProviderKey).toHaveBeenCalledWith("anthropic");
		expect(get(configuredIds).has("anthropic")).toBe(false);
	});

	it("surfaces the backend message and keeps state on failure", async () => {
		configuredIds.set(new Set(["anthropic"]));
		apiMocks.deleteProviderKey.mockRejectedValue(
			new Error("keychain delete failed: denied"),
		);

		const ok = await removeKey("anthropic");

		expect(ok).toBe(false);
		expect(get(actionErrors)["anthropic"]).toBe(
			"keychain delete failed: denied",
		);
		expect(get(configuredIds).has("anthropic")).toBe(true);
	});
});
