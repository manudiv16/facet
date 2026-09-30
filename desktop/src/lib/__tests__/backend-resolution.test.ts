// Regression coverage for the startup base-URL race.
//
// Components fire their data loads from `onMount`, which races the async
// `initBackend()` bootstrap. Before the fix the API client read the base URL
// synchronously, so a request issued while the backend was
// still `starting` either threw "Crystalline is not connected yet" (Tauri) or
// silently fell back to the dev URL (browser). `resolveBaseUrl()` awaits the
// bootstrap transition instead.
//
// Every case resets the module registry: `resolveBaseUrl` caches its promise at
// module scope, so each scenario needs a fresh instance of `backend`/`api`.
// `await import()` is required here (see `loadModules`) — that module boundary
// is exactly what these tests exercise.
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from "vitest";
import { get } from "svelte/store";

type FetchMock = Mock<(url: string, init?: RequestInit) => Promise<unknown>>;

/** Minimal `fetch` stand-in: always 200 with a JSON body. */
function stubFetch(body: unknown = {}): FetchMock {
	const fn = vi.fn(async (_url: string, _init?: RequestInit) => ({
		ok: true,
		status: 200,
		statusText: "OK",
		json: async () => body,
		text: async () => JSON.stringify(body),
	}));
	vi.stubGlobal("fetch", fn);
	return fn as unknown as FetchMock;
}

/** Fresh `backend` + `api` module instances sharing one module graph. */
async function loadModules() {
	const backendModule = await import("../backend");
	const apiModule = await import("../api");
	return { ...backendModule, api: apiModule.api };
}

beforeEach(() => {
	vi.resetModules();
});

afterEach(() => {
	vi.unstubAllGlobals();
	vi.unstubAllEnvs();
	vi.resetModules();
});

describe("resolveBaseUrl", () => {
	it("does not reject a request issued before the backend resolves; it waits and uses the resolved URL", async () => {
		const { backend, api } = await loadModules();
		const fetchMock = stubFetch({ flows: [] });

		const starting = get(backend);
		expect(starting.state).toBe("starting");

		let settle: "resolved" | "rejected" | null = null;
		const pending = api.get<{ flows: unknown[] }>("/flows").then(
			(value) => {
				settle = "resolved";
				return value;
			},
			(error) => {
				settle = "rejected";
				throw error;
			},
		);

		// Give the request every chance to fail fast, like the pre-fix code did.
		await Promise.resolve();
		await Promise.resolve();
		expect(settle).toBeNull();
		expect(fetchMock).not.toHaveBeenCalled();

		// Bootstrap completes: sidecar URL arrives through `facet://status`.
		backend.set({
			...starting,
			state: "ready",
			base_url: "http://127.0.0.1:49152",
		});

		await expect(pending).resolves.toEqual({ flows: [] });
		expect(fetchMock).toHaveBeenCalledTimes(1);
		expect(fetchMock.mock.calls[0][0]).toBe("http://127.0.0.1:49152/flows");
	});

	it("stays pending while the backend is starting and resolves null on error", async () => {
		const { backend, resolveBaseUrl } = await loadModules();
		const starting = get(backend);

		let settled: string | null = null;
		const pending = resolveBaseUrl().then((url) => {
			settled = `resolved:${url}`;
			return url;
		});

		await Promise.resolve();
		await Promise.resolve();
		expect(settled).toBeNull();

		backend.set({
			...starting,
			state: "error",
			error: "sidecar failed to start",
		});

		await expect(pending).resolves.toBeNull();
		expect(settled).toBe("resolved:null");
	});

	it("ignores a stale base URL when the backend is already in error", async () => {
		const { backend, resolveBaseUrl } = await loadModules();
		backend.set({
			...get(backend),
			state: "error",
			base_url: "http://127.0.0.1:49152",
			error: "sidecar died after reporting a port",
		});

		await expect(resolveBaseUrl()).resolves.toBeNull();
	});

	it("normalizes a configured base URL with a trailing slash", async () => {
		const { backend, api, resolveBaseUrl } = await loadModules();
		const fetchMock = stubFetch({ ok: true });

		backend.set({
			...get(backend),
			state: "ready",
			base_url: "http://127.0.0.1:8787/",
		});

		await expect(resolveBaseUrl()).resolves.toBe("http://127.0.0.1:8787");

		await api.get("/flows");
		expect(fetchMock.mock.calls[0][0]).toBe("http://127.0.0.1:8787/flows");
	});

	it("falls back to the browser URL when there is no Tauri runtime", async () => {
		vi.stubEnv("VITE_CRYSTALLINE_URL", "http://fallback.test:9999");
		const { resolveBaseUrl, initBackend } = await loadModules();

		// The request fires before `initBackend()` has run to completion.
		const pending = resolveBaseUrl();
		await initBackend();

		await expect(pending).resolves.toBe("http://fallback.test:9999");
	});
});
