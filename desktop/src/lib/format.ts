// Shared formatting helpers for execution and session-log views.

/** Parse an ISO-8601 string or a Unix timestamp (seconds or milliseconds). */
export function toDate(value: string | number | null | undefined): Date | null {
	if (value === null || value === undefined || value === "") return null;

	if (typeof value === "number") {
		return new Date(value < 1e12 ? value * 1000 : value);
	}

	// Numeric string → treat as Unix timestamp.
	if (/^\d+$/.test(value)) {
		const n = Number(value);
		return new Date(n < 1e12 ? n * 1000 : n);
	}

	const date = new Date(value);
	return Number.isNaN(date.getTime()) ? null : date;
}

/** Human-readable local timestamp, or an em dash when unavailable. */
export function formatTimestamp(value: string | number | null | undefined): string {
	const date = toDate(value);
	if (!date) return "—";
	return date.toLocaleString();
}

/** Short local time (used in the dense session log). */
export function formatTime(value: string | number | null | undefined): string {
	const date = toDate(value);
	if (!date) return "—";
	return date.toLocaleTimeString();
}

/** Duration in ms rendered as ms / s / m s. */
export function formatDuration(ms: number | null | undefined): string {
	if (ms === null || ms === undefined || Number.isNaN(ms)) return "—";
	if (ms < 1000) return `${Math.round(ms)}ms`;
	if (ms < 60_000) return `${(ms / 1000).toFixed(2)}s`;
	const minutes = Math.floor(ms / 60_000);
	const seconds = Math.round((ms % 60_000) / 1000);
	return `${minutes}m ${seconds}s`;
}

/** Duration between two timestamps, honouring a fallback duration in ms. */
export function formatSpan(
	start: string | number | null | undefined,
	end: string | number | null | undefined,
	fallbackMs?: number | null,
): string {
	const from = toDate(start);
	const to = toDate(end);
	if (from && to) return formatDuration(to.getTime() - from.getTime());
	if (fallbackMs !== undefined && fallbackMs !== null) return formatDuration(fallbackMs);
	return "—";
}

/** Thousands-separated integer. */
export function formatNumber(value: number | null | undefined): string {
	if (value === null || value === undefined || Number.isNaN(value)) return "0";
	return value.toLocaleString();
}

/** USD cost with enough precision to show sub-cent amounts. */
export function formatCost(value: number | null | undefined): string {
	if (value === null || value === undefined || Number.isNaN(value)) return "$0.00";
	if (value === 0) return "$0.00";
	if (Math.abs(value) < 0.01) return `$${value.toFixed(6)}`;
	return `$${value.toFixed(4)}`;
}
