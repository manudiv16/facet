// Svelte stores for the execution history table and the session log pane.
//
// The history store is a factory bound to a task; the log store is a factory
// bound to a single step execution. Both poll every 3s while work is active and
// stop as soon as every visible execution is terminal (C8 + F6 #3).
import { writable, get } from "svelte/store";
import type {
	Execution,
	ExecutionAggregate,
	SessionEvent,
	SessionLogResponse,
} from "./types";
import {
	listExecutions,
	listActiveExecutions,
	getExecution,
	getSessionLog,
	computeAggregate,
} from "./executions-api";

const POLL_INTERVAL = 3000; // 3 seconds
const HISTORY_PAGE_SIZE = 50;
const LOG_PAGE_SIZE = 100;

/** Statuses that mean the engine may still emit new rows/events. */
const ACTIVE_STATUSES = new Set([
	"pending",
	"entered",
	"in_progress",
	"running",
	"awaiting_input",
]);

/** Statuses after which no further updates are expected. */
const TERMINAL_STATUSES = new Set([
	"completed",
	"failed",
	"cancelled",
	"rejected",
]);

function isTerminal(status: string | null | undefined): boolean {
	return status !== null && status !== undefined && TERMINAL_STATUSES.has(status);
}

function isActive(status: string | null | undefined): boolean {
	if (!status) return false;
	if (TERMINAL_STATUSES.has(status)) return false;
	return ACTIVE_STATUSES.has(status) || !TERMINAL_STATUSES.has(status);
}

function sortBySequence<T extends { sequence: number }>(items: T[]): T[] {
	return [...items].sort((a, b) => a.sequence - b.sequence);
}

function errorMessage(e: unknown, fallback: string): string {
	if (e instanceof Error && e.message) return e.message;
	if (e && typeof e === "object" && "message" in e) {
		const message = (e as { message: unknown }).message;
		if (typeof message === "string" && message.length > 0) return message;
	}
	return fallback;
}

// ─── Execution history (per task) ───────────────────────────────────────────

export interface ExecutionHistoryStore {
	executions: ReturnType<typeof writable<Execution[]>>;
	aggregate: ReturnType<typeof writable<ExecutionAggregate>>;
	loading: ReturnType<typeof writable<boolean>>;
	loadingOlder: ReturnType<typeof writable<boolean>>;
	hasMore: ReturnType<typeof writable<boolean>>;
	polling: ReturnType<typeof writable<boolean>>;
	error: ReturnType<typeof writable<string | null>>;
	load: () => Promise<void>;
	loadOlder: () => Promise<void>;
	refreshExecution: (executionId: string) => Promise<void>;
	destroy: () => void;
}

function createExecutionHistoryStore(taskId: string): ExecutionHistoryStore {
	const executions = writable<Execution[]>([]);
	const aggregate = writable<ExecutionAggregate>(computeAggregate([]));
	const loading = writable(true);
	const loadingOlder = writable(false);
	const hasMore = writable(false);
	const polling = writable(false);
	const error = writable<string | null>(null);

	let intervalId: number | null = null;
	let oldestSequence: number | null = null;
	let loadedOlder = false;

	function applyFirstPage(list: Execution[], agg?: ExecutionAggregate) {
		executions.set(list);
		aggregate.set(agg ?? computeAggregate(list));
		oldestSequence =
			list.length > 0 && list[list.length - 1].sequence !== undefined
				? (list[list.length - 1].sequence as number)
				: null;
		loadedOlder = false;
	}

	async function load(): Promise<void> {
		loading.set(true);
		error.set(null);
		try {
			const res = await listExecutions(taskId, HISTORY_PAGE_SIZE);
			applyFirstPage(res.executions, res.aggregate);
			hasMore.set(res.has_more);
			if (res.executions.some((execution) => isActive(execution.status))) {
				startPolling();
			} else {
				stopPolling();
			}
		} catch (e) {
			error.set(errorMessage(e, "Failed to load execution history"));
		} finally {
			loading.set(false);
		}
	}

	/** Polling refresh: replace the newest page, keep older pages already shown. */
	async function refresh(): Promise<void> {
		try {
			const res = await listExecutions(taskId, HISTORY_PAGE_SIZE);
			const seen = new Set(res.executions.map((execution) => execution.id));
			executions.update((current) => [
				...res.executions,
				...current.filter((execution) => !seen.has(execution.id)),
			]);
			if (!loadedOlder) {
				aggregate.set(res.aggregate ?? computeAggregate(get(executions)));
				hasMore.set(res.has_more);
				oldestSequence =
					res.executions.length > 0 &&
					res.executions[res.executions.length - 1].sequence !== undefined
						? (res.executions[res.executions.length - 1].sequence as number)
						: oldestSequence;
			} else {
				aggregate.set(computeAggregate(get(executions)));
			}
			error.set(null);
			if (!get(executions).some((execution) => isActive(execution.status))) {
				stopPolling();
			}
		} catch {
			// Keep the last good state on transient polling failures.
		}
	}

	async function loadOlder(): Promise<void> {
		if (!get(hasMore) || get(loadingOlder) || oldestSequence === null) return;
		loadingOlder.set(true);
		error.set(null);
		try {
			const res = await listExecutions(taskId, HISTORY_PAGE_SIZE, oldestSequence);
			const seen = new Set(get(executions).map((execution) => execution.id));
			const older = res.executions.filter((execution) => !seen.has(execution.id));
			// Newest-first: older rows are appended below the current ones.
			executions.update((current) => [...current, ...older]);
			hasMore.set(res.has_more);
			aggregate.set(computeAggregate(get(executions)));
			loadedOlder = true;
			if (older.length > 0 && older[older.length - 1].sequence !== undefined) {
				oldestSequence = older[older.length - 1].sequence as number;
			}
		} catch (e) {
			error.set(errorMessage(e, "Failed to load older executions"));
		} finally {
			loadingOlder.set(false);
		}
	}

	async function refreshExecution(executionId: string): Promise<void> {
		try {
			const fresh = await getExecution(executionId);
			executions.update((current) =>
				current.map((execution) =>
					execution.id === executionId ? fresh : execution,
				),
			);
		} catch {
			// Best-effort: the list refresh will reconcile shortly.
		}
	}

	function startPolling() {
		if (intervalId !== null) return;
		intervalId = window.setInterval(() => void refresh(), POLL_INTERVAL);
		polling.set(true);
	}

	function stopPolling() {
		if (intervalId !== null) {
			clearInterval(intervalId);
			intervalId = null;
		}
		polling.set(false);
	}

	function destroy() {
		stopPolling();
	}

	return {
		executions,
		aggregate,
		loading,
		loadingOlder,
		hasMore,
		polling,
		error,
		load,
		loadOlder,
		refreshExecution,
		destroy,
	};
}

// ─── Active executions (overview fallback) ──────────────────────────────────

export function createActiveExecutionsStore() {
	const executions = writable<Execution[]>([]);
	const loading = writable(true);
	const error = writable<string | null>(null);
	let intervalId: number | null = null;

	async function load() {
		loading.set(true);
		error.set(null);
		try {
			const res = await listActiveExecutions(HISTORY_PAGE_SIZE);
			executions.set(res.executions);
			if (res.executions.length > 0) startPolling();
			else stopPolling();
		} catch (e) {
			error.set(errorMessage(e, "Failed to load active executions"));
		} finally {
			loading.set(false);
		}
	}

	async function refresh() {
		try {
			const res = await listActiveExecutions(HISTORY_PAGE_SIZE);
			executions.set(res.executions);
			if (res.executions.length === 0) stopPolling();
		} catch {
			// keep last state
		}
	}

	function startPolling() {
		if (intervalId !== null) return;
		intervalId = window.setInterval(() => void refresh(), POLL_INTERVAL);
	}

	function stopPolling() {
		if (intervalId !== null) {
			clearInterval(intervalId);
			intervalId = null;
		}
	}

	return { executions, loading, error, load, refresh, destroy: stopPolling };
}

// ─── Session log (per execution) ────────────────────────────────────────────

export interface SessionLogStore {
	events: ReturnType<typeof writable<SessionEvent[]>>;
	loading: ReturnType<typeof writable<boolean>>;
	loadingOlder: ReturnType<typeof writable<boolean>>;
	hasMore: ReturnType<typeof writable<boolean>>;
	polling: ReturnType<typeof writable<boolean>>;
	error: ReturnType<typeof writable<string | null>>;
	init: (status?: string) => Promise<void>;
	loadOlder: () => Promise<void>;
	updateStatus: (status: string) => void;
	destroy: () => void;
}

function createSessionLogStore(executionId: string): SessionLogStore {
	const events = writable<SessionEvent[]>([]);
	const loading = writable(true);
	const loadingOlder = writable(false);
	const hasMore = writable(false);
	const polling = writable(false);
	const error = writable<string | null>(null);

	let intervalId: number | null = null;
	let oldestSequence: number | null = null;
	let stopped = false;

	function applyPage(res: SessionLogResponse, prepend: boolean) {
		const incoming = sortBySequence(res.events);
		if (prepend) {
			// Older page: prepend while keeping chronological order.
			events.update((current) => mergeEvents(incoming, current));
		} else {
			events.set(incoming);
		}
		hasMore.set(res.has_more);
		if (incoming.length > 0) oldestSequence = incoming[0].sequence;
		else if (!prepend) oldestSequence = null;
	}

	async function loadInitial() {
		loading.set(true);
		error.set(null);
		try {
			const res = await getSessionLog(executionId, LOG_PAGE_SIZE);
			applyPage(res, false);
		} catch (e) {
			error.set(errorMessage(e, "Failed to load session log"));
		} finally {
			loading.set(false);
		}
	}

	async function loadOlder() {
		if (!get(hasMore) || get(loadingOlder) || oldestSequence === null) return;
		loadingOlder.set(true);
		error.set(null);
		try {
			const res = await getSessionLog(executionId, LOG_PAGE_SIZE, oldestSequence);
			applyPage(res, true);
		} catch (e) {
			error.set(errorMessage(e, "Failed to load older events"));
		} finally {
			loadingOlder.set(false);
		}
	}

	async function poll() {
		try {
			const res = await getSessionLog(executionId, LOG_PAGE_SIZE);
			const current = get(events);
			const newest = current.length > 0 ? current[current.length - 1].sequence : 0;
			const fresh = res.events.filter((event) => event.sequence > newest);
			if (fresh.length > 0) {
				events.update((prev) => mergeEvents(prev, fresh));
			}
		} catch {
			// Ignore transient polling failures.
		}
	}

	function startPolling() {
		if (intervalId !== null || stopped) return;
		intervalId = window.setInterval(() => void poll(), POLL_INTERVAL);
		polling.set(true);
	}

	function stopPolling() {
		if (intervalId !== null) {
			clearInterval(intervalId);
			intervalId = null;
		}
		polling.set(false);
	}

	async function init(status: string = "pending") {
		stopped = isTerminal(status);
		await loadInitial();
		if (!stopped) startPolling();
	}

	function updateStatus(status: string) {
		if (isTerminal(status)) {
			stopped = true;
			stopPolling();
		} else if (!stopped) {
			startPolling();
		}
	}

	function destroy() {
		stopped = true;
		stopPolling();
	}

	return {
		events,
		loading,
		loadingOlder,
		hasMore,
		polling,
		error,
		init,
		loadOlder,
		updateStatus,
		destroy,
	};
}

function mergeEvents(
	current: SessionEvent[],
	incoming: SessionEvent[],
): SessionEvent[] {
	const byId = new Map<string, SessionEvent>();
	for (const event of current) byId.set(event.id, event);
	for (const event of incoming) byId.set(event.id, event);
	return sortBySequence(Array.from(byId.values()));
}

// ─── Factory exports ────────────────────────────────────────────────────────

export function useExecutionHistory(taskId: string): ExecutionHistoryStore {
	return createExecutionHistoryStore(taskId);
}

export function useSessionLog(executionId: string): SessionLogStore {
	return createSessionLogStore(executionId);
}
