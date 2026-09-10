// Connection to the Crystalline backend.
//
// Inside Tauri the app bootstraps the sidecar (or a remote instance) and the
// resolved base URL arrives through the `get_config` command / `facet://status`
// events. In a plain browser (`vite dev` without Tauri) we fall back to an
// environment variable so the UI can still be developed.
import { writable, get } from "svelte/store";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export type BackendState = "starting" | "ready" | "error";
export type BackendMode = "embedded" | "remote";

export interface BackendStatus {
	state: BackendState;
	mode: BackendMode;
	base_url: string | null;
	port: number | null;
	version: string | null;
	error: string | null;
}

const BROWSER_FALLBACK_URL =
	import.meta.env.VITE_CRYSTALLINE_URL || "http://localhost:8787";

const initial: BackendStatus = {
	state: "starting",
	mode: "embedded",
	base_url: null,
	port: null,
	version: null,
	error: null,
};

export const backend = writable<BackendStatus>(initial);

interface TauriWindow {
	__TAURI_INTERNALS__?: unknown;
}

export function isTauri(): boolean {
	return (
		typeof window !== "undefined" &&
		Boolean((window as TauriWindow).__TAURI_INTERNALS__)
	);
}

/** Base URL used by the API client, or `null` while the backend is not ready. */
export function getBaseUrl(): string | null {
	const status = get(backend);
	if (status.base_url) {
		return status.state === "error" ? null : status.base_url.replace(/\/$/, "");
	}
	// Browser fallback (no Tauri runtime).
	return isTauri() ? null : BROWSER_FALLBACK_URL;
}

let started = false;

/** Resolve the backend once and subscribe to status updates. */
export async function initBackend(): Promise<void> {
	if (started) return;
	started = true;

	if (!isTauri()) {
		backend.set({
			...initial,
			state: "ready",
			mode: "remote",
			base_url: BROWSER_FALLBACK_URL,
		});
		return;
	}

	await listen<BackendStatus>("facet://status", (event) => {
		backend.set(event.payload);
	});

	try {
		const status = await invoke<BackendStatus>("get_config");
		backend.set(status);
	} catch (error) {
		backend.set({
			...initial,
			state: "error",
			error: `Failed to read backend configuration: ${String(error)}`,
		});
	}
}
