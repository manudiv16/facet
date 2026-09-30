// Svelte stores for the execution history table and the session log pane.
//
// The history store is a factory bound to a task; the log store is a factory
// bound to a single step execution. Both are fed by the engine's Server-Sent
// Events stream (C20, see `lib/execution-stream`): the REST page loads first
// and the stream applies transitions and appends log rows as they happen.
//
// There is no polling any more. Everything a stream cannot vouch for — a cursor
// jump, a reconnect, an engine restart — arrives as a gap and re-pages the REST
// backlog, and the refresh controls cover the cases the stream does not cover
// at all (the cross-task active list has no per-execution stream to subscribe
// to).
import { writable, get, type Writable } from "svelte/store";
import type {
	Execution,
	ExecutionAggregate,
	ExecutionStatus,
	SessionEvent,
	SessionLogResponse,
} from "./types";
import {
	listExecutions,
	listActiveExecutions,
	getExecution,
	getSessionLog,
	computeAggregate,
	normalizeSessionEvent,
} from "./executions-api";
import { resolveBaseUrl } from "./backend";
import {
	authToken,
	createExecutionStream,
	type ExecutionStream,
	type ExecutionStreamFrame,
	type StepStatusFrame,
	type StreamGap,
	type StreamState,
} from "./execution-stream";
import { toDate } from "./format";

const HISTORY_PAGE_SIZE = 50;
const LOG_PAGE_SIZE = 100;
/** Coalescing window for the REST resync a flow transition triggers. */
const FLOW_RESYNC_MS = 1000;

/** Statuses after which no further updates are expected. */
const TERMINAL_STATUSES: Record<string, true> = {
	completed: true,
	failed: true,
	cancelled: true,
	rejected: true,
};

function isTerminal(status: string | null | undefined): boolean {
	return status !== null && status !== undefined && TERMINAL_STATUSES[status] === true;
}

/** A known, non-terminal status: the engine may still emit updates for it. */
function isActive(status: string | null | undefined): boolean {
	return typeof status === "string" && status.length > 0 && !isTerminal(status);
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

/** Latest `execution_status` transition of the flow behind a task's history. */
export interface FlowStatus {
	status: ExecutionStatus;
	current_node_id: string | null;
	updated_at: number | null;
}

// ─── Execution history (per task) ───────────────────────────────────────────

export interface ExecutionHistoryStore {
	executions: Writable<Execution[]>;
	aggregate: Writable<ExecutionAggregate>;
	loading: Writable<boolean>;
	loadingOlder: Writable<boolean>;
	hasMore: Writable<boolean>;
	/** The flow stream is connected and frames are flowing. */
	live: Writable<boolean>;
	/** Newest flow-level transition seen on the stream. */
	flow: Writable<FlowStatus | null>;
	/** Set when the stream could not cover the range; the store resynced. */
	gap: Writable<StreamGap | null>;
	error: Writable<string | null>;
	load: () => Promise<void>;
	loadOlder: () => Promise<void>;
	/** Re-page the newest REST page (manual refresh and gap recovery). */
	refresh: () => Promise<void>;
	refreshExecution: (executionId: string) => Promise<void>;
	/** Apply a `step_status` frame forwarded by the session log store. */
	applyStepStatus: (frame: StepStatusFrame) => void;
	destroy: () => void;
}

function createExecutionHistoryStore(taskId: string): ExecutionHistoryStore {
	const executions = writable<Execution[]>([]);
	const aggregate = writable<ExecutionAggregate>(computeAggregate([]));
	const loading = writable(true);
	const loadingOlder = writable(false);
	const hasMore = writable(false);
	const live = writable(false);
	const flow = writable<FlowStatus | null>(null);
	const gap = writable<StreamGap | null>(null);
	const error = writable<string | null>(null);

	let oldestSequence: number | null = null;
	let loadedOlder = false;
	let destroyed = false;

	// The flow stream follows the task's execution state: `execution_status`
	// transitions of the flow, which is how a step row appears or changes
	// without polling. When a row has no state id the row's own id is used
	// instead, so the same slot delivers its `step_status` transitions.
	let flowStream: ExecutionStream | null = null;
	let flowStreamId: string | null = null;
	let resyncTimer: number | null = null;

	function stopFlowStream(): void {
		flowStream?.close();
		flowStream = null;
		flowStreamId = null;
		live.set(false);
	}

	function scheduleResync(): void {
		if (resyncTimer !== null || destroyed) return;
		resyncTimer = window.setTimeout(() => {
			resyncTimer = null;
			void refresh();
		}, FLOW_RESYNC_MS);
	}

	function applyStepStatus(frame: StepStatusFrame): void {
		const completed = toDate(frame.completed_at);
		executions.update((current) =>
			current.map((row) =>
				row.id === frame.execution_id
					? {
							...row,
							status: frame.status,
							output: frame.output ?? row.output,
							completed_at: completed
								? completed.toISOString()
								: row.completed_at,
						}
					: row,
			),
		);
	}

	function handleFlowFrame(frame: ExecutionStreamFrame): void {
		if (frame.type === "execution_status") {
			flow.set({
				status: frame.status,
				current_node_id: frame.current_node_id,
				updated_at: frame.updated_at,
			});
			// A transition usually creates or rewrites a step row.
			scheduleResync();
		} else if (frame.type === "step_status") {
			applyStepStatus(frame);
		}
	}

	async function connectFlowStream(stateId: string): Promise<void> {
		const base = await resolveBaseUrl();
		if (!base || destroyed || flowStreamId !== stateId) return;
		const stream = createExecutionStream({
			executionId: stateId,
			baseUrl: base,
			token: authToken(),
			handlers: {
				onFrame: handleFlowFrame,
				onGap: (streamGap) => {
					gap.set(streamGap);
					void refresh();
				},
				onState: (state: StreamState) => live.set(state === "open"),
			},
		});
		flowStream = stream;
		stream.start();
	}

	function ensureFlowStream(): void {
		if (destroyed) return;
		const rows = get(executions);
		const activeRow = rows.find((row) => isActive(row.status));
		const streamId = activeRow?.execution_state_id ?? activeRow?.id ?? null;
		if (streamId === null) {
			stopFlowStream();
			return;
		}
		if (streamId === flowStreamId) return;
		stopFlowStream();
		flowStreamId = streamId;
		void connectFlowStream(streamId);
	}

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
			gap.set(null);
			ensureFlowStream();
		} catch (e) {
			error.set(errorMessage(e, "Failed to load execution history"));
		} finally {
			loading.set(false);
		}
	}

	/** Resync: replace the newest page, keep older pages already shown. */
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
			ensureFlowStream();
		} catch {
			// Keep the last good state on a transient resync failure.
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
			// Best-effort: the REST resync will reconcile shortly.
		}
	}

	function destroy() {
		destroyed = true;
		stopFlowStream();
		if (resyncTimer !== null) {
			window.clearTimeout(resyncTimer);
			resyncTimer = null;
		}
	}

	return {
		executions,
		aggregate,
		loading,
		loadingOlder,
		hasMore,
		live,
		flow,
		gap,
		error,
		load,
		loadOlder,
		refresh,
		refreshExecution,
		applyStepStatus,
		destroy,
	};
}

// ─── Active executions (overview fallback) ──────────────────────────────────
//
// The stream is keyed per execution, so a cross-task list has nothing to
// subscribe to; this store loads on mount and on demand (`refresh`), and the
// page refreshes it when the window regains focus.

export function createActiveExecutionsStore() {
	const executions = writable<Execution[]>([]);
	const loading = writable(true);
	const error = writable<string | null>(null);

	async function load() {
		loading.set(true);
		error.set(null);
		try {
			const res = await listActiveExecutions(HISTORY_PAGE_SIZE);
			executions.set(res.executions);
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
			error.set(null);
		} catch {
			// keep the last good state
		}
	}

	return { executions, loading, error, load, refresh };
}

// ─── Session log (per execution) ────────────────────────────────────────────

export interface SessionLogStoreOptions {
	/** Forwarded `step_status` frames, so the history row updates in place. */
	onStepStatus?: (frame: StepStatusFrame) => void;
}

export interface SessionLogStore {
	events: Writable<SessionEvent[]>;
	loading: Writable<boolean>;
	loadingOlder: Writable<boolean>;
	hasMore: Writable<boolean>;
	/** The stream is connected and frames are flowing. */
	live: Writable<boolean>;
	streamState: Writable<StreamState>;
	/** Set when the stream could not cover the range; the store resynced. */
	gap: Writable<StreamGap | null>;
	error: Writable<string | null>;
	init: (status?: string) => Promise<void>;
	loadOlder: () => Promise<void>;
	/** Re-page the newest REST page (manual refresh and gap recovery). */
	refresh: () => Promise<void>;
	updateStatus: (status: string) => void;
	destroy: () => void;
}

function createSessionLogStore(
	executionId: string,
	options: SessionLogStoreOptions = {},
): SessionLogStore {
	const events = writable<SessionEvent[]>([]);
	const loading = writable(true);
	const loadingOlder = writable(false);
	const hasMore = writable(false);
	const live = writable(false);
	const streamState = writable<StreamState>("idle");
	const gap = writable<StreamGap | null>(null);
	const error = writable<string | null>(null);

	let oldestSequence: number | null = null;
	let stopped = false;
	let destroyed = false;
	let stream: ExecutionStream | null = null;

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

	/** Merge the newest REST page: recovers everything the stream missed. */
	async function refresh(): Promise<void> {
		try {
			const res = await getSessionLog(executionId, LOG_PAGE_SIZE);
			events.update((current) => mergeEvents(current, res.events));
			error.set(null);
		} catch (e) {
			error.set(errorMessage(e, "Failed to refresh session log"));
		}
	}

	function handleFrame(frame: ExecutionStreamFrame): void {
		if (frame.type === "session_log") {
			const event = normalizeSessionEvent(frame.log);
			events.update((current) => mergeEvents(current, [event]));
		} else if (frame.type === "step_status") {
			options.onStepStatus?.(frame);
		}
	}

	function stopStream(): void {
		stream?.close();
		stream = null;
		live.set(false);
	}

	async function ensureStream(): Promise<void> {
		if (stopped || destroyed || stream !== null) return;
		const base = await resolveBaseUrl();
		if (!base || stopped || destroyed || stream !== null) return;
		const created = createExecutionStream({
			executionId,
			baseUrl: base,
			token: authToken(),
			handlers: {
				onFrame: handleFrame,
				onGap: (streamGap) => {
					gap.set(streamGap);
					void refresh();
				},
				onState: (state: StreamState) => {
					streamState.set(state);
					live.set(state === "open");
				},
			},
		});
		stream = created;
		created.start();
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

	async function init(status: string = "pending") {
		stopped = isTerminal(status);
		gap.set(null);
		await loadInitial();
		if (!stopped) await ensureStream();
	}

	function updateStatus(status: string) {
		if (isTerminal(status)) {
			stopped = true;
			stopStream();
		} else if (!stopped) {
			void ensureStream();
		}
	}

	function destroy() {
		destroyed = true;
		stopped = true;
		stopStream();
	}

	return {
		events,
		loading,
		loadingOlder,
		hasMore,
		live,
		streamState,
		gap,
		error,
		init,
		loadOlder,
		refresh,
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

export function useSessionLog(
	executionId: string,
	options: SessionLogStoreOptions = {},
): SessionLogStore {
	return createSessionLogStore(executionId, options);
}
