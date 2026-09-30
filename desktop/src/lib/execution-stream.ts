// Server-Sent Events client for one execution's live update stream.
//
// Crystalline exposes `GET /api/v1/executions/:id/events` as an SSE stream
// (engine C20, `http/execution_stream.gleam`): the first frame is always
// `stream_opened` (`{"execution_id", "latest_sequence"}`), then
// `execution_status`, `step_status` and `session_log` frames — each carrying an
// `event_sequence` cursor — plus `keep_alive` heartbeats. `:id` is either a step
// execution id or an execution state id; events are keyed per execution id, so
// a step subscription sees that step's `step_status`/`session_log` frames and a
// state subscription sees the flow's `execution_status` frames.
//
// This module owns everything transport-shaped, so the stores stay about state:
//   - URL building (`?after_sequence=`, `?token=`);
//   - typed parsing of the three event kinds;
//   - the last-sequence cursor (duplicates from a resumed replay are dropped);
//   - gap detection — a sequence jump, a re-established connection, or an
//     engine restart that reset the cursor;
//   - `onerror` reconnection with exponential backoff, resuming from the cursor.
//
// The stream is best-effort and in-memory (the engine's replay buffer is
// bounded), so a gap means "fall back to the REST backlog" — the caller
// re-pages `GET /api/v1/executions/:id/logs`.
//
// The token goes into the query string because `EventSource` cannot set request
// headers. It is a secret: this module never logs it and never renders it —
// `redactedUrl()` is the only URL it hands out for display or messages.
import { API_PREFIX } from "./executions-api";
import type { ExecutionStatus } from "./types";

/** SSE event names the engine emits on an execution stream. */
export const STREAM_EVENT_NAMES = [
	"stream_opened",
	"execution_status",
	"step_status",
	"session_log",
] as const;

/** Placeholder substituted for the token whenever a URL may be displayed. */
export const REDACTED_TOKEN = "REDACTED";

// ─── Frames ─────────────────────────────────────────────────────────────────

/** Opening frame: the subscription is registered and this cursor was reported. */
export interface StreamOpenedFrame {
	type: "stream_opened";
	execution_id: string;
	latest_sequence: number;
}

/** Flow-level transition of an execution state (subscribe with a state id). */
export interface ExecutionStatusFrame {
	type: "execution_status";
	event_sequence: number;
	execution_id: string;
	status: ExecutionStatus;
	current_node_id: string | null;
	updated_at: number | null;
}

/** One step execution moved to a new status (subscribe with a step id). */
export interface StepStatusFrame {
	type: "step_status";
	event_sequence: number;
	execution_id: string;
	node_id: string;
	/** Step status, which is a subset of `ExecutionStatus`. */
	status: ExecutionStatus;
	output: string | null;
	session_id: string | null;
	completed_at: number | null;
}

/** Raw session-log row as carried inside a `session_log` frame. */
export interface SessionLogRow {
	id: string;
	step_execution_id: string;
	task_id: string;
	event_type: string;
	/** JSON payload string, decoded by `normalizeSessionEvent`. */
	payload: string;
	/** The log's per-step sequence, which is also the REST paging cursor. */
	sequence: number;
	created_at: number;
}

/** A session-log row was appended for a step execution. */
export interface SessionLogFrame {
	type: "session_log";
	event_sequence: number;
	execution_id: string;
	log: SessionLogRow;
}

export type ExecutionStreamFrame =
	| StreamOpenedFrame
	| ExecutionStatusFrame
	| StepStatusFrame
	| SessionLogFrame;

// ─── Gaps ───────────────────────────────────────────────────────────────────

export type StreamGapReason =
	/** `event_sequence` skipped: the engine's buffer no longer covers the range. */
	| "sequence_gap"
	/** The connection was re-established; the buffer may not cover the outage. */
	| "reconnect"
	/** The cursor went backwards: the engine restarted and reset its registry. */
	| "restart";

export interface StreamGap {
	reason: StreamGapReason;
	/** Cursor the client expected next, when known. */
	expected_sequence: number | null;
	/** Sequence the stream resumed at, when known. */
	received_sequence: number | null;
}

// ─── Connection state ───────────────────────────────────────────────────────

export type StreamState =
	/** Created but not started yet. */
	| "idle"
	/** First connection attempt in flight. */
	| "connecting"
	/** `stream_opened` received; frames are flowing. */
	| "open"
	/** Lost (or retrying) a connection that had already opened. */
	| "reconnecting"
	/** Closed by the caller; no further attempts. */
	| "closed";

// ─── Decoding helpers ───────────────────────────────────────────────────────

function asRecord(value: unknown): Record<string, unknown> {
	return value !== null && typeof value === "object" && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: {};
}

function text(value: unknown): string | null {
	return typeof value === "string" && value.length > 0 ? value : null;
}

function optionalText(value: unknown): string | null {
	return typeof value === "string" ? value : null;
}

function integer(value: unknown): number | null {
	return typeof value === "number" && Number.isFinite(value)
		? Math.trunc(value)
		: null;
}

function parseObject(data: string): Record<string, unknown> | null {
	if (typeof data !== "string" || data.length === 0) return null;
	try {
		const parsed: unknown = JSON.parse(data);
		if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
			return null;
		}
		return parsed as Record<string, unknown>;
	} catch {
		return null;
	}
}

/**
 * Decode one SSE frame into a typed frame, or `null` for the frames this client
 * ignores (`keep_alive` heartbeats, unknown event names, malformed payloads).
 *
 * @param eventName The SSE `event:` name.
 * @param data The raw SSE `data:` payload.
 */
export function parseStreamFrame(
	eventName: string,
	data: string,
): ExecutionStreamFrame | null {
	const record = parseObject(data);
	if (!record) return null;

	// The `event:` name is authoritative; `data.type` is the same value and
	// covers a transport that drops the name.
	switch (text(eventName) ?? text(record.type)) {
		case "stream_opened":
			return {
				type: "stream_opened",
				execution_id: text(record.execution_id) ?? "",
				latest_sequence: integer(record.latest_sequence) ?? 0,
			};

		case "execution_status": {
			const eventSequence = integer(record.event_sequence);
			if (eventSequence === null) return null;
			return {
				type: "execution_status",
				event_sequence: eventSequence,
				execution_id: text(record.execution_id) ?? "",
				status: (text(record.status) ?? "pending") as ExecutionStatus,
				current_node_id: optionalText(record.current_node_id),
				updated_at: integer(record.updated_at),
			};
		}

		case "step_status": {
			const eventSequence = integer(record.event_sequence);
			if (eventSequence === null) return null;
			return {
				type: "step_status",
				event_sequence: eventSequence,
				execution_id: text(record.execution_id) ?? "",
				node_id: text(record.node_id) ?? "",
				status: (text(record.status) ?? "pending") as ExecutionStatus,
				output: optionalText(record.output),
				session_id: optionalText(record.session_id),
				completed_at: integer(record.completed_at),
			};
		}

		case "session_log": {
			const eventSequence = integer(record.event_sequence);
			if (eventSequence === null) return null;
			// The engine nests the row under `session_log`; a flattened payload
			// is accepted too so this decoder survives either shape.
			const row = asRecord(record.session_log ?? record);
			return {
				type: "session_log",
				event_sequence: eventSequence,
				execution_id: text(record.execution_id) ?? "",
				log: {
					id: text(row.id) ?? "",
					step_execution_id:
						text(row.step_execution_id) ?? text(record.execution_id) ?? "",
					task_id: text(row.task_id) ?? "",
					event_type: text(row.event_type) ?? "text",
					payload:
						typeof row.payload === "string"
							? row.payload
							: JSON.stringify(row.payload ?? ""),
					sequence: integer(row.sequence) ?? 0,
					created_at: integer(row.created_at) ?? 0,
				},
			};
		}

		default:
			return null;
	}
}

// ─── URL building ───────────────────────────────────────────────────────────

export interface StreamUrlOptions {
	/** Resume cursor: buffered events above this sequence are replayed. */
	afterSequence?: number | null;
	/** Bearer token; `EventSource` cannot send an `Authorization` header. */
	token?: string | null;
}

/**
 * Build the stream URL for one execution.
 *
 * When `token` is set the returned URL contains the secret (the engine accepts
 * `?token=` on this route and only this route) — display `redactedUrl()`
 * instead of logging the result.
 */
export function buildExecutionStreamUrl(
	baseUrl: string,
	executionId: string,
	options: StreamUrlOptions = {},
): string {
	const params = new URLSearchParams();
	if (options.afterSequence !== undefined && options.afterSequence !== null) {
		params.set("after_sequence", String(options.afterSequence));
	}
	if (options.token) params.set("token", options.token);
	const query = params.toString();
	const path = `${API_PREFIX}/executions/${encodeURIComponent(executionId)}/events`;
	return `${baseUrl.replace(/\/+$/, "")}${path}${query ? `?${query}` : ""}`;
}

/**
 * Replace the `token` query parameter with a placeholder.
 *
 * Used for every URL the UI renders or logs; `connectExecutionStream` passes
 * the real URL straight to `EventSource` and keeps it local.
 */
export function redactStreamUrl(url: string): string {
	const marker = "token=";
	const at = url.indexOf(marker);
	if (at === -1) return url;
	const end = url.indexOf("&", at);
	const tail = end === -1 ? "" : url.slice(end);
	return `${url.slice(0, at)}${marker}${REDACTED_TOKEN}${tail}`;
}

/**
 * The token the app holds for a remote Crystalline instance.
 *
 * Mirrors `api.ts`, which sends the same value as `Authorization: Bearer …` on
 * the REST calls — the URL-fragment form is the SSE equivalent.
 */
export function authToken(): string | null {
	const token = import.meta.env.VITE_CRYSTALLINE_TOKEN;
	return typeof token === "string" && token.length > 0 ? token : null;
}

// ─── Reconnection backoff ───────────────────────────────────────────────────

export interface StreamBackoff {
	/** Delay before the first retry, in milliseconds. */
	initialMs: number;
	/** Multiplier applied per consecutive failed attempt. */
	factor: number;
	/** Upper bound for the delay, in milliseconds. */
	maxMs: number;
}

export const DEFAULT_BACKOFF: StreamBackoff = {
	initialMs: 1000,
	factor: 2,
	maxMs: 30_000,
};

/** Delay before retry number `attempt` (1-based), capped at `maxMs`. */
export function backoffDelay(
	attempt: number,
	backoff: StreamBackoff = DEFAULT_BACKOFF,
): number {
	const exponent = Math.max(0, attempt - 1);
	return Math.min(backoff.maxMs, backoff.initialMs * backoff.factor ** exponent);
}

// ─── Client ─────────────────────────────────────────────────────────────────

export interface ExecutionStreamHandlers {
	/** Every parsed frame, in sequence order and without duplicates. */
	onFrame: (frame: ExecutionStreamFrame) => void;
	/** The stream could not be trusted to cover the range; resync over REST. */
	onGap?: (gap: StreamGap) => void;
	onState?: (state: StreamState) => void;
}

export interface ExecutionStreamOptions {
	executionId: string;
	/** Crystalline base URL (no trailing slash required). */
	baseUrl: string;
	token?: string | null;
	/** Cursor to resume from; only reconnects update it on their own. */
	afterSequence?: number | null;
	handlers: ExecutionStreamHandlers;
	backoff?: StreamBackoff;
}

export interface ExecutionStream {
	readonly executionId: string;
	/** Open the connection. Idempotent; a no-op after `close()`. */
	start: () => void;
	/** Close and never reconnect. */
	close: () => void;
	state: () => StreamState;
	/** Highest `event_sequence` observed, or the initial cursor. */
	lastSequence: () => number | null;
	/** URL with the token redacted — safe to log, render or report. */
	redactedUrl: () => string;
}

/**
 * Open the execution event stream and keep it open.
 *
 * Frames are delivered through `handlers.onFrame` in sequence order; a cursor
 * jump, a re-established connection or an engine restart that reset the cursor
 * (reported through `handlers.onGap`) all mean the client must fall back to the
 * REST backlog.
 */
export function createExecutionStream(
	options: ExecutionStreamOptions,
): ExecutionStream {
	const { executionId, baseUrl, handlers } = options;
	const token = options.token ?? authToken();
	const backoff = options.backoff ?? DEFAULT_BACKOFF;

	let source: EventSource | null = null;
	let state: StreamState = "idle";
	let lastSequence: number | null = options.afterSequence ?? null;
	let attempt = 0;
	let opened = false;
	let closed = false;
	/** The next open replays from scratch after an engine restart. */
	let restarting = false;
	let timer: number | null = null;

	function setState(next: StreamState): void {
		if (state === next) return;
		state = next;
		handlers.onState?.(next);
	}

	function emitGap(gap: StreamGap): void {
		handlers.onGap?.(gap);
	}

	function url(after: number | null, secret: boolean): string {
		return buildExecutionStreamUrl(baseUrl, executionId, {
			afterSequence: after,
			token: secret ? token : token ? REDACTED_TOKEN : null,
		});
	}

	function handleOpened(frame: StreamOpenedFrame): void {
		const reconnected = opened;
		opened = true;
		if (reconnected) {
			if (lastSequence !== null && frame.latest_sequence < lastSequence) {
				// The engine restarted: its registry reset the cursor, so the
				// buffered range no longer exists. Report the gap, drop the stale
				// cursor and reconnect without one to replay what is buffered.
				emitGap({
					reason: "restart",
					expected_sequence: null,
					received_sequence: frame.latest_sequence,
				});
				lastSequence = null;
				restarting = true;
				reconnect(0);
				return;
			}
			// A reconnect whose outage the bounded buffer may not cover: the
			// engine only filters duplicates, it does not tell us what it lost.
			// The restart reply above already reported its own gap.
			if (!restarting) {
				emitGap({
					reason: "reconnect",
					expected_sequence:
						lastSequence === null ? null : lastSequence + 1,
					received_sequence: frame.latest_sequence,
				});
			}
		}
		restarting = false;
		attempt = 0;
		setState("open");
		handlers.onFrame(frame);
	}

	function handleMessage(name: string, data: string): void {
		const frame = parseStreamFrame(name, data);
		if (!frame) return;
		if (frame.type === "stream_opened") {
			handleOpened(frame);
			return;
		}
		const sequence = frame.event_sequence;
		// A resume can overlap with events published while resubscribing; the
		// cursor makes delivery exactly-once per subscriber.
		if (lastSequence !== null && sequence <= lastSequence) return;
		if (lastSequence !== null && sequence > lastSequence + 1) {
			emitGap({
				reason: "sequence_gap",
				expected_sequence: lastSequence + 1,
				received_sequence: sequence,
			});
		}
		lastSequence = sequence;
		handlers.onFrame(frame);
	}

	function open(): void {
		if (closed) return;
		if (typeof EventSource === "undefined") {
			setState("closed");
			return;
		}
		// A restart re-opens while the stale connection is still live.
		source?.close();
		const next = new EventSource(url(lastSequence, true));
		source = next;
		for (const name of STREAM_EVENT_NAMES) {
			next.addEventListener(name, (event) =>
				handleMessage(name, String((event as MessageEvent).data ?? "")),
			);
		}
		next.onerror = () => {
			// Close first: the browser's own reconnect would ignore our cursor
			// and backoff, so this client owns the retry schedule.
			next.close();
			if (source === next) source = null;
			if (closed) return;
			reconnect();
		};
	}

	function reconnect(delay?: number): void {
		if (closed || timer !== null) return;
		const wait = delay ?? backoffDelay(attempt + 1, backoff);
		attempt += 1;
		setState("reconnecting");
		timer = setTimeout(() => {
			timer = null;
			open();
		}, wait);
	}

	function start(): void {
		if (closed || state !== "idle") return;
		setState("connecting");
		open();
	}

	function close(): void {
		closed = true;
		if (timer !== null) {
			clearTimeout(timer);
			timer = null;
		}
		source?.close();
		source = null;
		setState("closed");
	}

	return {
		executionId,
		start,
		close,
		state: () => state,
		lastSequence: () => lastSequence,
		redactedUrl: () => url(lastSequence, false),
	};
}
