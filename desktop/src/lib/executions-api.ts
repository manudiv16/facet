// Executions API — HTTP access to the Crystalline execution/session-log
// endpoints (Crystalline C8, `http/routes/executions.gleam`).
//
// Endpoint contract:
//   GET  /api/v1/tasks/:id/executions   step history, newest first (?limit&before_sequence)
//   GET  /api/v1/executions/active      running + awaiting_input
//   GET  /api/v1/executions/:id         one execution with metrics
//   GET  /api/v1/executions/:id/logs    session log page (?limit&before_sequence)
//
// The wire format is normalised here so the stores and components only ever see
// the canonical shapes from `$lib/types`. `event_type` + JSON `payload` become
// `kind` + `data`; `created_at` Unix seconds become ISO `timestamp`/`started_at`.
import { api } from "./api";
import { toDate } from "./format";
import type {
	Execution,
	ExecutionAggregate,
	ExecutionListResponse,
	ExecutionStatus,
	SessionEvent,
	SessionEventData,
	SessionEventKind,
	SessionLogResponse,
} from "./types";

export const API_PREFIX = "/api/v1";

type Raw = Record<string, unknown>;

// ─── Decoding helpers ───────────────────────────────────────────────────────

function asRecord(value: unknown): Raw {
	return value !== null && typeof value === "object"
		? (value as Raw)
		: {};
}

function asArray(value: unknown): unknown[] {
	return Array.isArray(value) ? value : [];
}

function str(value: unknown, fallback = ""): string {
	return typeof value === "string" ? value : fallback;
}

function optionalStr(value: unknown): string | null {
	return typeof value === "string" && value.length > 0 ? value : null;
}

function num(value: unknown, fallback = 0): number {
	return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function bool(value: unknown, fallback = false): boolean {
	return typeof value === "boolean" ? value : fallback;
}

/** Coerce Unix seconds/ms or an ISO string into an ISO string. */
function isoTime(value: unknown): string | null {
	const date = toDate(value as string | number | null | undefined);
	return date ? date.toISOString() : optionalStr(value);
}

function firstDefined(...values: unknown[]): unknown {
	for (const value of values) {
		if (value !== undefined && value !== null && value !== "") return value;
	}
	return undefined;
}

// ─── Execution normalisation ────────────────────────────────────────────────

export function normalizeExecution(raw: unknown): Execution {
	const r = asRecord(raw);
	return {
		id: str(r.id),
		task_id: str(r.task_id),
		flow_instance_id: optionalStr(
			firstDefined(r.flow_instance_id, r.flow_id, r.instance_id),
		),
		execution_state_id: optionalStr(
			firstDefined(r.execution_state_id, r.execution_id, r.flow_execution_id),
		),
		node_id: str(firstDefined(r.node_id, r.node, r.node_name)),
		status: str(r.status, "pending") as ExecutionStatus,
		model: optionalStr(r.model),
		input_tokens: num(firstDefined(r.input_tokens, r.tokens_in)),
		output_tokens: num(firstDefined(r.output_tokens, r.tokens_out)),
		cost: num(r.cost),
		duration_ms: num(r.duration_ms),
		started_at: isoTime(firstDefined(r.started_at, r.created_at)),
		completed_at: isoTime(r.completed_at),
		prompt: optionalStr(r.prompt),
		output: optionalStr(r.output),
		error: optionalStr(r.error),
		sequence:
			typeof r.sequence === "number" && Number.isFinite(r.sequence)
				? r.sequence
				: undefined,
	};
}

function normalizeAggregate(raw: unknown, fallback: ExecutionAggregate): ExecutionAggregate {
	const r = asRecord(raw);
	if (Object.keys(r).length === 0) return fallback;
	return {
		total_input_tokens: num(r.total_input_tokens, fallback.total_input_tokens),
		total_output_tokens: num(r.total_output_tokens, fallback.total_output_tokens),
		total_cost: num(r.total_cost, fallback.total_cost),
		total_duration_ms: num(r.total_duration_ms, fallback.total_duration_ms),
	};
}

export function computeAggregate(executions: Execution[]): ExecutionAggregate {
	return executions.reduce<ExecutionAggregate>(
		(acc, execution) => {
			acc.total_input_tokens += execution.input_tokens;
			acc.total_output_tokens += execution.output_tokens;
			acc.total_cost += execution.cost;
			acc.total_duration_ms += execution.duration_ms;
			return acc;
		},
		{
			total_input_tokens: 0,
			total_output_tokens: 0,
			total_cost: 0,
			total_duration_ms: 0,
		},
	);
}

function normalizeExecutionList(
	payload: unknown,
	limit: number,
): ExecutionListResponse {
	const r = asRecord(payload);
	const rawItems = Array.isArray(payload)
		? payload
		: firstDefined(r.executions, r.items, r.steps, r.data);
	const executions = asArray(rawItems).map(normalizeExecution);
	const hasMore =
		typeof r.has_more === "boolean"
			? r.has_more
			: typeof r.hasMore === "boolean"
				? r.hasMore
				: executions.length >= limit;
	return {
		executions,
		has_more: hasMore,
		aggregate: normalizeAggregate(r.aggregate, computeAggregate(executions)),
	};
}

// ─── Session log normalisation ──────────────────────────────────────────────

function parsePayload(payload: unknown): Raw {
	if (typeof payload === "string") {
		try {
			const parsed: unknown = JSON.parse(payload);
			if (parsed !== null && typeof parsed === "object") return parsed as Raw;
			return { content: parsed };
		} catch {
			return { content: payload };
		}
	}
	return asRecord(payload);
}

function normalizeEventData(kind: SessionEventKind, payload: unknown): SessionEventData {
	const p = parsePayload(payload);
	switch (kind) {
		case "tool_use":
			return {
				tool_name: str(firstDefined(p.tool_name, p.name, p.tool)),
				tool_input: asRecord(firstDefined(p.tool_input, p.input, p.arguments)),
			};
		case "tool_result":
			return {
				tool_name: str(firstDefined(p.tool_name, p.name, p.tool)),
				output: str(firstDefined(p.output, p.content, p.result)),
				truncated: bool(p.truncated),
			};
		case "usage":
			return {
				input_tokens: num(firstDefined(p.input_tokens, p.input)),
				output_tokens: num(firstDefined(p.output_tokens, p.output)),
			};
		case "outcome":
			return {
				success: p.success === undefined ? true : bool(p.success, true),
				result: optionalStr(firstDefined(p.result, p.output)) ?? undefined,
			};
		case "error":
			return {
				error_type: str(firstDefined(p.error_type, p.type), "error"),
				message: str(
					firstDefined(p.message, p.error, p.detail),
					typeof payload === "string" ? payload : "",
				),
				stack: optionalStr(p.stack) ?? undefined,
			};
		case "text":
		default:
			return {
				content: str(
					firstDefined(p.content, p.text),
					typeof payload === "string" ? payload : "",
				),
			};
	}
}

const EVENT_KINDS: readonly SessionEventKind[] = [
	"text",
	"tool_use",
	"tool_result",
	"usage",
	"outcome",
	"error",
];

function normalizeEventKind(value: unknown): SessionEventKind {
	const kind = str(value, "text");
	return (EVENT_KINDS as readonly string[]).includes(kind)
		? (kind as SessionEventKind)
		: "text";
}

export function normalizeSessionEvent(raw: unknown): SessionEvent {
	const r = asRecord(raw);
	const kind = normalizeEventKind(firstDefined(r.kind, r.event_type, r.type));
	const payload = firstDefined(
		r.data,
		r.payload,
		r.payload_json,
		r.details,
		r.content,
	);
	const base = {
		id: str(r.id),
		execution_id: str(
			firstDefined(r.execution_id, r.step_execution_id, r.executionId),
		),
		sequence: num(r.sequence),
		timestamp: isoTime(firstDefined(r.timestamp, r.created_at)) ?? "",
	};
	// The discriminant + data pair is correlated at runtime; cast the assembled
	// object to the discriminated union.
	return {
		...base,
		kind,
		data: normalizeEventData(kind, payload),
	} as SessionEvent;
}

function normalizeSessionLog(
	payload: unknown,
	limit: number,
): SessionLogResponse {
	const r = asRecord(payload);
	const rawItems = Array.isArray(payload)
		? payload
		: firstDefined(r.events, r.logs, r.items, r.data);
	const events = asArray(rawItems).map(normalizeSessionEvent);
	const hasMore =
		typeof r.has_more === "boolean"
			? r.has_more
			: typeof r.hasMore === "boolean"
				? r.hasMore
				: events.length >= limit;
	return { events, has_more: hasMore };
}

// ─── API functions ──────────────────────────────────────────────────────────

/** `GET /api/v1/tasks/:id/executions` — step history, newest first. */
export async function listExecutions(
	taskId: string,
	limit = 50,
	beforeSequence?: number,
): Promise<ExecutionListResponse> {
	const params = new URLSearchParams({ limit: String(limit) });
	if (beforeSequence !== undefined) {
		params.set("before_sequence", String(beforeSequence));
	}
	const payload = await api.get<unknown>(
		`${API_PREFIX}/tasks/${encodeURIComponent(taskId)}/executions?${params}`,
	);
	return normalizeExecutionList(payload, limit);
}

/** `GET /api/v1/executions/active` — running + awaiting_input. */
export async function listActiveExecutions(
	limit = 50,
): Promise<ExecutionListResponse> {
	const params = new URLSearchParams({ limit: String(limit) });
	const payload = await api.get<unknown>(
		`${API_PREFIX}/executions/active?${params}`,
	);
	return normalizeExecutionList(payload, limit);
}

/** `GET /api/v1/executions/:id` — one execution with metrics. */
export async function getExecution(executionId: string): Promise<Execution> {
	const payload = await api.get<unknown>(
		`${API_PREFIX}/executions/${encodeURIComponent(executionId)}`,
	);
	return normalizeExecution(payload);
}

/** `GET /api/v1/executions/:id/logs` — session log page. */
export async function getSessionLog(
	executionId: string,
	limit = 100,
	beforeSequence?: number,
): Promise<SessionLogResponse> {
	const params = new URLSearchParams({ limit: String(limit) });
	if (beforeSequence !== undefined) {
		params.set("before_sequence", String(beforeSequence));
	}
	const payload = await api.get<unknown>(
		`${API_PREFIX}/executions/${encodeURIComponent(executionId)}/logs?${params}`,
	);
	return normalizeSessionLog(payload, limit);
}
