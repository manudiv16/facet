// Provider API keys: metadata plus the bridge to the Tauri keychain commands.
//
// Keys are write-only from the frontend: `setProviderKey` sends a value to
// Rust, which stores it in the OS keychain, and the only thing that ever
// comes back is the list of provider ids that have a key — never key
// material, so a saved key cannot be echoed into the DOM.
import { invoke } from "@tauri-apps/api/core";
import { isTauri } from "./backend";

export interface ProviderInfo {
	/** Stable id; mirrors `Provider::id` in src-tauri/src/secrets.rs. */
	id: string;
	/** Display name. */
	label: string;
	/** Env var the embedded sidecar receives; mirrors `Provider::env_var`. */
	envVar: string;
	/** Placeholder hinting at the expected key shape. */
	placeholder: string;
	/** Where the user creates or revokes a key. */
	keysUrl: string;
}

export const PROVIDERS: ProviderInfo[] = [
	{
		id: "anthropic",
		label: "Anthropic",
		envVar: "ANTHROPIC_API_KEY",
		placeholder: "sk-ant-…",
		keysUrl: "https://console.anthropic.com/settings/keys",
	},
	{
		id: "openai",
		label: "OpenAI",
		envVar: "OPENAI_API_KEY",
		placeholder: "sk-…",
		keysUrl: "https://platform.openai.com/api-keys",
	},
	{
		id: "google",
		label: "Google",
		envVar: "GOOGLE_API_KEY",
		placeholder: "AIza…",
		keysUrl: "https://aistudio.google.com/apikey",
	},
	{
		id: "groq",
		label: "Groq",
		envVar: "GROQ_API_KEY",
		placeholder: "gsk_…",
		keysUrl: "https://console.groq.com/keys",
	},
	{
		id: "mistral",
		label: "Mistral",
		envVar: "MISTRAL_API_KEY",
		placeholder: "Paste key…",
		keysUrl: "https://console.mistral.ai/api-keys",
	},
	{
		id: "openrouter",
		label: "OpenRouter",
		envVar: "OPENROUTER_API_KEY",
		placeholder: "sk-or-…",
		keysUrl: "https://openrouter.ai/keys",
	},
];

// Tauri commands reject with plain strings (`Result<_, String>` on the Rust
// side); normalize so callers always get an Error with a usable message.
function asError(error: unknown): Error {
	if (error instanceof Error) return error;
	return new Error(typeof error === "string" ? error : String(error));
}

const DESKTOP_ONLY =
	"Provider keys live in the OS keychain and can only be managed in the Facet desktop app.";

/** Ids of the providers with a key in the OS keychain (names only). */
export async function listConfiguredProviders(): Promise<string[]> {
	if (!isTauri()) throw new Error(DESKTOP_ONLY);
	try {
		return await invoke<string[]>("list_provider_keys");
	} catch (error) {
		throw asError(error);
	}
}

/** Store (or replace) a provider key in the OS keychain. */
export async function setProviderKey(id: string, key: string): Promise<void> {
	if (!isTauri()) throw new Error(DESKTOP_ONLY);
	try {
		await invoke("set_provider_key", { provider: id, key });
	} catch (error) {
		throw asError(error);
	}
}

/** Remove a provider key from the OS keychain. */
export async function deleteProviderKey(id: string): Promise<void> {
	if (!isTauri()) throw new Error(DESKTOP_ONLY);
	try {
		await invoke("delete_provider_key", { provider: id });
	} catch (error) {
		throw asError(error);
	}
}
