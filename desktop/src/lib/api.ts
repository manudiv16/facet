// API client for Crystalline backend
import { getBaseUrl } from "./backend";

export interface ApiError {
	message: string;
	status: number;
}

async function request<T>(
	endpoint: string,
	options: RequestInit = {},
): Promise<T> {
	const base = getBaseUrl();
	if (!base) {
		throw {
			message: "Crystalline is not connected yet",
			status: 0,
		} as ApiError;
	}

	const url = `${base}${endpoint}`;
	const token = import.meta.env.VITE_CRYSTALLINE_TOKEN;

	const headers: Record<string, string> = {
		"Content-Type": "application/json",
		...(options.headers as Record<string, string>),
	};

	if (token) {
		headers["Authorization"] = `Bearer ${token}`;
	}

	const response = await fetch(url, { ...options, headers });

	if (!response.ok) {
		throw { message: await extractErrorMessage(response), status: response.status } as ApiError;
	}

	return response.json();
}

/**
 * Pull the human-readable message out of an error response.
 *
 * Crystalline returns `{"error": "..."}`; fall back to the raw body (or the
 * status text) when the payload is not JSON so the UI always has something to
 * show inline.
 */
async function extractErrorMessage(response: Response): Promise<string> {
	const text = await response.text();
	if (text) {
		try {
			const parsed: unknown = JSON.parse(text);
			if (
				parsed &&
				typeof parsed === "object" &&
				"error" in parsed &&
				typeof (parsed as { error: unknown }).error === "string"
			) {
				return (parsed as { error: string }).error;
			}
			if (
				parsed &&
				typeof parsed === "object" &&
				"message" in parsed &&
				typeof (parsed as { message: unknown }).message === "string"
			) {
				return (parsed as { message: string }).message;
			}
		} catch {
			// Not JSON — keep the raw text below.
		}
		return text;
	}
	return response.statusText || `Request failed with status ${response.status}`;
}

export const api = {
	get: <T>(endpoint: string) => request<T>(endpoint),
	post: <T>(endpoint: string, data: unknown) =>
		request<T>(endpoint, { method: "POST", body: JSON.stringify(data) }),
	patch: <T>(endpoint: string, data: unknown) =>
		request<T>(endpoint, { method: "PATCH", body: JSON.stringify(data) }),
	delete: <T>(endpoint: string) => request<T>(endpoint, { method: "DELETE" }),
};
