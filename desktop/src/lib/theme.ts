import { writable } from "svelte/store";

export type Theme = "light" | "dark";

const STORAGE_KEY = "facet:theme";

function initialTheme(): Theme {
	if (typeof localStorage !== "undefined") {
		const stored = localStorage.getItem(STORAGE_KEY);
		if (stored === "light" || stored === "dark") return stored;
	}
	if (
		typeof window !== "undefined" &&
		window.matchMedia?.("(prefers-color-scheme: dark)").matches
	) {
		return "dark";
	}
	return "dark";
}

export const theme = writable<Theme>(initialTheme());

theme.subscribe((value) => {
	if (typeof document !== "undefined") {
		document.documentElement.dataset.theme = value;
	}
	if (typeof localStorage !== "undefined") {
		localStorage.setItem(STORAGE_KEY, value);
	}
});

export function toggleTheme(): void {
	theme.update((current) => (current === "dark" ? "light" : "dark"));
}
