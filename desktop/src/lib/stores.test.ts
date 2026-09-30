// C20 acceptance tests for the execution history / session log stores.
//
// Verifies the behaviour behind the acceptance criteria:
//   - a completed flow renders via one row per step with correct totals
//     (history store aggregates);
//   - page 2 (older) loads arrive via limit+before_sequence and are appended
//     without duplicates, keeping a single ordering invariant;
//   - the stores no longer poll: the REST backlog loads first and the engine's
//     event stream applies transitions and appends log rows as they arrive;
//   - a stream gap re-pages the REST backlog instead of trusting the stream.
//
// `EventSource` itself is covered by `execution-stream.test.ts`; here the
// stream factory is faked so the store's frame handling is what is under test.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { get } from "svelte/store";
import type { Execution, SessionEvent } from "./types";
import type {
	ExecutionStream,
	ExecutionStreamFrame,
	ExecutionStreamHandlers,
	StreamGap,
	StreamState,
} from "./execution-stream";

const mocks = vi.hoisted(() => ({
	listExecutions: vi.fn(),
	listActiveExecutions: vi.fn(),
	getExecution: vi.fn(),
	getSessionLog: vi.fn(),
	createExecutionStream: vi.fn(),
}));

vi.mock("./executions-api", async () => {
	const actual =
		await vi.importActual<typeof import("./executions-api")>(
			"./executions-api",
		);
	return {
		...actual,
		listExecutions: mocks.listExecutions,
		listActiveExecutions: mocks.listActiveExecutions,
		getExecution: mocks.getExecution,
		getSessionLog: mocks.getSessionLog,
	};
});

vi.mock("./backend", () => ({
	resolveBaseUrl: () => Promise.resolve("http://127.0.0.1:8787"),
}));

vi.mock("./execution-stream", async () => {
	const actual =
		await vi.importActual<typeof import("./execution-stream")>(
			"./execution-stream",
		);
	return {
		...actual,
		authToken: () => null,
		createExecutionStream: mocks.createExecutionStream,
	};
});

import {
	createActiveExecutionsStore,
	useExecutionHistory,
	useSessionLog,
} from "./stores";

/** A fake of the SSE client, exposing the handlers the store registered. */
class FakeStream implements ExecutionStream {
	readonly executionId: string;
	readonly handlers: ExecutionStreamHandlers;
	started = false;
	stopped = false;
	currentState: StreamState = "idle";

	constructor(options: {
		executionId: string;
		handlers: ExecutionStreamHandlers;
	}) {
		this.executionId = options.executionId;
		this.handlers = options.handlers;
	}

	start(): void {
		this.started = true;
	}

	close(): void {
		this.stopped = true;
	}

	state(): StreamState {
		return this.currentState;
	}

	lastSequence(): number | null {
		return null;
	}

	redactedUrl(): string {
		return `http://127.0.0.1:8787/api/v1/executions/${this.executionId}/events`;
	}

	frame(frame: ExecutionStreamFrame): void {
		this.handlers.onFrame(frame);
	}

	open(): void {
		this.currentState = "open";
		this.handlers.onState?.("open");
	}

	gap(gap: StreamGap): void {
		this.handlers.onGap?.(gap);
	}
}

let streams: FakeStream[] = [];

/** Let the store's `await resolveBaseUrl()` and stream creation settle. */
async function settle(): Promise<void> {
	for (let tick = 0; tick < 4; tick++) await Promise.resolve();
}

beforeEach(() => {
	vi.resetAllMocks();
	vi.useFakeTimers();
	streams = [];
	mocks.createExecutionStream.mockImplementation(
		(options: { executionId: string; handlers: ExecutionStreamHandlers }) => {
			const stream = new FakeStream(options);
			streams.push(stream);
			return stream;
		},
	);
	// The stores schedule their debounce/resync via `window.*` timers; under the
	// node environment the browser global is absent, so hand them the faked one.
	vi.stubGlobal("window", {
		setTimeout: globalThis.setTimeout,
		clearTimeout: globalThis.clearTimeout,
	});
});

afterEach(() => {
	vi.useRealTimers();
	vi.unstubAllGlobals();
});

function execRow(seq: number, overrides: Partial<Execution> = {}): Execution {
	return {
		id: `s-${seq}`,
		task_id: "task-1",
		node_id: `node-${seq}`,
		status: "completed",
		model: "claude-sonnet-4",
		input_tokens: 100,
		output_tokens: 20,
		cost: 0.01,
		duration_ms: 1000,
		started_at: "2025-07-01T10:00:00.000Z",
		completed_at: "2025-07-01T10:00:01.000Z",
		sequence: seq,
		...overrides,
	};
}

/** Newest-first page: `from` down to `to` (inclusive), as the API returns. */
function execPage(from: number, to: number): Execution[] {
	const rows: Execution[] = [];
	for (let seq = from; seq >= to; seq--) rows.push(execRow(seq));
	return rows;
}

function eventRow(seq: number): SessionEvent {
	return {
		id: `ev-${seq}`,
		execution_id: "exec-1",
		sequence: seq,
		timestamp: `2025-07-01T10:00:${String(seq % 60).padStart(2, "0")}.000Z`,
		kind: "text",
		data: { content: `event ${seq}` },
	};
}

/** Newest-first page of log events: `from` down to `to`. */
function eventPage(from: number, to: number): SessionEvent[] {
	const rows: SessionEvent[] = [];
	for (let seq = from; seq >= to; seq--) rows.push(eventRow(seq));
	return rows;
}

/** A `session_log` frame as the engine publishes it for one log row. */
function sessionLogFrame(seq: number): ExecutionStreamFrame {
	return {
		type: "session_log",
		event_sequence: seq,
		execution_id: "exec-1",
		log: {
			id: `ev-${seq}`,
			step_execution_id: "exec-1",
			task_id: "task-1",
			event_type: "text",
			payload: JSON.stringify({ content: `event ${seq}` }),
			sequence: seq,
			created_at: 1_751_234_567_000,
		},
	};
}

describe("execution history store", () => {
	it("loads one row per completed step with correct footer totals and no stream", async () => {
		mocks.listExecutions.mockResolvedValue({
			executions: [
				execRow(2, {
					id: "step-a",
					node_id: "build",
					input_tokens: 1500,
					output_tokens: 300,
					cost: 0.0412,
					duration_ms: 8120,
				}),
				execRow(1, {
					id: "step-b",
					node_id: "review",
					input_tokens: 1200,
					output_tokens: 220,
					cost: 0.022,
					duration_ms: 5330,
				}),
			],
			has_more: false,
		});

		const store = useExecutionHistory("task-1");
		await store.load();
		await settle();

		expect(get(store.executions)).toHaveLength(2);
		expect(get(store.executions).map((e) => e.node_id)).toEqual([
			"build",
			"review",
		]);
		expect(get(store.aggregate)).toEqual({
			total_input_tokens: 2700,
			total_output_tokens: 520,
			total_cost: 0.0632,
			total_duration_ms: 13450,
		});
		expect(get(store.hasMore)).toBe(false);
		// Nothing is running: there is no execution to stream.
		expect(mocks.createExecutionStream).not.toHaveBeenCalled();
		store.destroy();
	});

	it("streams the active flow and resyncs the list on a transition", async () => {
		mocks.listExecutions
			.mockResolvedValueOnce({
				executions: [
					execRow(1, {
						id: "step-1",
						status: "in_progress",
						execution_state_id: "state-1",
					}),
				],
				has_more: false,
			})
			.mockResolvedValueOnce({
				executions: [
					execRow(2, {
						id: "step-2",
						status: "awaiting_input",
						execution_state_id: "state-1",
					}),
					execRow(1, {
						id: "step-1",
						status: "completed",
						execution_state_id: "state-1",
					}),
				],
				has_more: false,
			});

		const store = useExecutionHistory("task-1");
		await store.load();
		await settle();

		expect(streams).toHaveLength(1);
		expect(streams[0].executionId).toBe("state-1");
		expect(streams[0].started).toBe(true);

		streams[0].open();
		expect(get(store.live)).toBe(true);

		streams[0].frame({
			type: "execution_status",
			event_sequence: 1,
			execution_id: "state-1",
			status: "running",
			current_node_id: "build",
			updated_at: 1_751_234_567_000,
		});
		expect(get(store.flow)).toEqual({
			status: "running",
			current_node_id: "build",
			updated_at: 1_751_234_567_000,
		});

		// The transition is coalesced into one REST resync, which brings in the
		// step the flow just entered — the polling replacement.
		await vi.advanceTimersByTimeAsync(1000);
		expect(mocks.listExecutions).toHaveBeenCalledTimes(2);
		expect(get(store.executions).map((e) => e.id)).toEqual(["step-2", "step-1"]);
		store.destroy();
	});

	it("applies a step_status frame to its row in place", async () => {
		mocks.listExecutions.mockResolvedValue({
			executions: [
				execRow(1, {
					id: "step-1",
					status: "in_progress",
					execution_state_id: "state-1",
					completed_at: null,
				}),
			],
			has_more: false,
		});

		const store = useExecutionHistory("task-1");
		await store.load();
		await settle();

		store.applyStepStatus({
			type: "step_status",
			event_sequence: 4,
			execution_id: "step-1",
			node_id: "build",
			status: "completed",
			output: "done",
			session_id: "sess-1",
			completed_at: 1_751_234_567_000,
		});

		const row = get(store.executions)[0];
		expect(row.status).toBe("completed");
		expect(row.output).toBe("done");
		expect(row.completed_at).toBe(
			new Date(1_751_234_567_000).toISOString(),
		);
		// A frame for an unknown execution is ignored, not appended.
		store.applyStepStatus({
			type: "step_status",
			event_sequence: 5,
			execution_id: "someone-else",
			node_id: "other",
			status: "completed",
			output: null,
			session_id: null,
			completed_at: null,
		});
		expect(get(store.executions)).toHaveLength(1);
		store.destroy();
	});

	it("resyncs over REST when the stream reports a gap", async () => {
		mocks.listExecutions
			.mockResolvedValueOnce({
				executions: [execRow(1, { id: "step-1", status: "in_progress" })],
				has_more: false,
			})
			.mockResolvedValueOnce({
				executions: [
					execRow(2, { id: "step-2", status: "completed" }),
					execRow(1, { id: "step-1", status: "completed" }),
				],
				has_more: false,
			});

		const store = useExecutionHistory("task-1");
		await store.load();
		await settle();

		streams[0].gap({
			reason: "reconnect",
			expected_sequence: 3,
			received_sequence: 9,
		});
		await settle();

		expect(get(store.gap)?.reason).toBe("reconnect");
		expect(mocks.listExecutions).toHaveBeenCalledTimes(2);
		expect(get(store.executions).map((e) => e.id)).toEqual(["step-2", "step-1"]);
		store.destroy();
	});

	it("appends page 2 via before_sequence without duplicates and recomputes totals", async () => {
		mocks.listExecutions
			.mockResolvedValueOnce({ executions: execPage(120, 71), has_more: true })
			.mockResolvedValueOnce({ executions: execPage(70, 21), has_more: false });

		const store = useExecutionHistory("task-1");
		await store.load();
		expect(get(store.executions)).toHaveLength(50);
		expect(get(store.hasMore)).toBe(true);

		await store.loadOlder();

		expect(mocks.listExecutions).toHaveBeenLastCalledWith("task-1", 50, 71);
		const all = get(store.executions);
		expect(all).toHaveLength(100);
		// Newest-first invariant holds across the appended pages.
		const sequences = all.map((e) => e.sequence!);
		expect(sequences[0]).toBe(120);
		expect(sequences[99]).toBe(21);
		expect(new Set(sequences).size).toBe(100);
		expect(get(store.hasMore)).toBe(false);
		// Totals now span both pages (100 rows × 100 in / 20 out / $0.01).
		const agg = get(store.aggregate);
		expect(agg.total_input_tokens).toBe(10_000);
		expect(agg.total_output_tokens).toBe(2_000);
		// Floating cost sums accumulate rounding error; compare within tolerance.
		expect(agg.total_cost).toBeCloseTo(1);
		expect(agg.total_duration_ms).toBe(100_000);
		store.destroy();
	});
});

describe("session log store", () => {
	it("loads the REST backlog first, then appends streamed events in order", async () => {
		mocks.getSessionLog.mockResolvedValue({
			events: eventPage(100, 99),
			has_more: true,
		});

		const store = useSessionLog("exec-1");
		await store.init("in_progress");
		await settle();

		// The backlog is on screen before the stream starts.
		expect(get(store.events).map((e) => e.sequence)).toEqual([99, 100]);
		expect(get(store.hasMore)).toBe(true);
		expect(streams).toHaveLength(1);
		expect(streams[0].executionId).toBe("exec-1");
		expect(streams[0].started).toBe(true);

		streams[0].open();
		expect(get(store.live)).toBe(true);
		expect(get(store.streamState)).toBe("open");

		streams[0].frame(sessionLogFrame(101));
		streams[0].frame(sessionLogFrame(102));
		// A duplicate row (resume overlap) must not be appended twice.
		streams[0].frame(sessionLogFrame(102));

		const all = get(store.events);
		expect(all.map((e) => e.sequence)).toEqual([99, 100, 101, 102]);
		expect(all[3].kind).toBe("text");
		expect(all[3].data).toEqual({ content: "event 102" });
		expect(get(store.hasMore)).toBe(true);
		store.destroy();
	});

	it("does not open a stream for an execution that already finished", async () => {
		mocks.getSessionLog.mockResolvedValue({
			events: eventPage(3, 1),
			has_more: false,
		});

		const store = useSessionLog("exec-1");
		await store.init("completed");
		await settle();

		expect(mocks.createExecutionStream).not.toHaveBeenCalled();
		expect(get(store.live)).toBe(false);
		expect(get(store.streamState)).toBe("idle");
		store.destroy();
	});

	it("closes the stream once the execution reaches a terminal status", async () => {
		mocks.getSessionLog.mockResolvedValue({ events: [], has_more: false });

		const store = useSessionLog("exec-1");
		await store.init("in_progress");
		await settle();
		streams[0].open();
		expect(get(store.live)).toBe(true);

		store.updateStatus("completed");

		expect(streams[0].stopped).toBe(true);
		expect(get(store.live)).toBe(false);
		// No reconnect is attempted once the stream is closed.
		expect(mocks.createExecutionStream).toHaveBeenCalledTimes(1);
		store.destroy();
	});

	it("re-pages the REST backlog when the stream reports a gap", async () => {
		mocks.getSessionLog
			.mockResolvedValueOnce({ events: eventPage(3, 1), has_more: false })
			.mockResolvedValueOnce({ events: eventPage(6, 1), has_more: false });

		const store = useSessionLog("exec-1");
		await store.init("in_progress");
		await settle();
		streams[0].frame(sessionLogFrame(4));

		streams[0].gap({
			reason: "sequence_gap",
			expected_sequence: 5,
			received_sequence: 9,
		});
		await settle();

		expect(get(store.gap)?.reason).toBe("sequence_gap");
		// The REST page is authoritative after a gap: the missed rows 5 and 6
		// arrive, ordered, without duplicating 1..4.
		expect(get(store.events).map((e) => e.sequence)).toEqual([
			1, 2, 3, 4, 5, 6,
		]);
		store.destroy();
	});

	it("forwards step transitions to the caller so the history row follows", async () => {
		mocks.getSessionLog.mockResolvedValue({ events: [], has_more: false });
		const onStepStatus = vi.fn();

		const store = useSessionLog("exec-1", { onStepStatus });
		await store.init("in_progress");
		await settle();

		const frame: ExecutionStreamFrame = {
			type: "step_status",
			event_sequence: 2,
			execution_id: "exec-1",
			node_id: "build",
			status: "completed",
			output: "done",
			session_id: null,
			completed_at: 1_751_234_567_000,
		};
		streams[0].frame(frame);

		expect(onStepStatus).toHaveBeenCalledWith(frame);
		// Flow-level frames belong to the history store, not the log feed.
		streams[0].frame({
			type: "execution_status",
			event_sequence: 3,
			execution_id: "state-1",
			status: "running",
			current_node_id: "build",
			updated_at: 1_751_234_567_000,
		});
		expect(get(store.events)).toEqual([]);
		store.destroy();
	});
});

describe("active executions store", () => {
	it("loads the cross-task list on demand and on refresh", async () => {
		mocks.listActiveExecutions
			.mockResolvedValueOnce({
				executions: [execRow(1, { id: "step-1", status: "running" })],
				has_more: false,
			})
			.mockResolvedValueOnce({ executions: [], has_more: false });

		const store = createActiveExecutionsStore();
		await store.load();
		expect(get(store.executions)).toHaveLength(1);

		await store.refresh();
		expect(get(store.executions)).toHaveLength(0);
	});
});
