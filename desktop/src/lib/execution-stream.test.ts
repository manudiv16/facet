// C20 acceptance tests for the execution event stream client.
//
// Covers the transport contract the executions screen depends on, with
// `EventSource` faked (no sockets):
//   - URL building carries the execution id, the `after_sequence` cursor and
//     the `?token=` the engine accepts on this route only;
//   - all three event kinds decode into typed frames, in sequence order;
//   - duplicates from a resumed replay are dropped and a cursor jump is
//     reported as a gap;
//   - a reconnect resumes from the last observed `event_sequence`, with
//     exponential backoff, and reports the gap so the caller re-pages REST;
//   - a restarted engine (cursor reset) is reported as a `restart` gap;
//   - the token never reaches a log or a rendered URL.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	backoffDelay,
	buildExecutionStreamUrl,
	createExecutionStream,
	DEFAULT_BACKOFF,
	parseStreamFrame,
	redactStreamUrl,
	type ExecutionStreamFrame,
	type StreamGap,
	type StreamState,
} from "./execution-stream";

// ─── Fake EventSource ───────────────────────────────────────────────────────

type Listener = (event: MessageEvent) => void;

class FakeEventSource {
	static instances: FakeEventSource[] = [];

	readonly url: string;
	closed = false;
	onerror: ((event: Event) => void) | null = null;
	private listeners = new Map<string, Listener[]>();

	constructor(url: string) {
		this.url = url;
		FakeEventSource.instances.push(this);
	}

	addEventListener(type: string, listener: Listener): void {
		const current = this.listeners.get(type) ?? [];
		this.listeners.set(type, [...current, listener]);
	}

	close(): void {
		this.closed = true;
	}

	/** Deliver an SSE frame the way the browser does: `event:` + `data:`. */
	emit(type: string, data: unknown): void {
		const payload = typeof data === "string" ? data : JSON.stringify(data);
		for (const listener of this.listeners.get(type) ?? []) {
			listener({ data: payload } as MessageEvent);
		}
	}

	/** Drop the connection the way a network failure or engine shutdown does. */
	fail(): void {
		this.onerror?.(new Event("error"));
	}

	static reset(): void {
		FakeEventSource.instances = [];
	}

	static get latest(): FakeEventSource {
		const instance =
			FakeEventSource.instances[FakeEventSource.instances.length - 1];
		if (!instance) throw new Error("no EventSource was created");
		return instance;
	}
}

// Real frames, as captured from `GET /api/v1/executions/:id/events`.
const OPENED = {
	execution_id: "step-sse",
	latest_sequence: 0,
};
const SESSION_LOG_FRAME = {
	event_sequence: 1,
	type: "session_log",
	execution_id: "step-sse",
	session_log: {
		id: "log-1",
		step_execution_id: "step-sse",
		task_id: "task-sse",
		event_type: "text",
		payload: "e2e-hello",
		sequence: 1,
		created_at: 1_759_000_000_000,
	},
};
const STEP_STATUS_FRAME = {
	event_sequence: 2,
	type: "step_status",
	execution_id: "step-sse",
	node_id: "build",
	status: "in_progress",
	output: null,
	session_id: "sess-1",
	completed_at: null,
};
const EXECUTION_STATUS_FRAME = {
	event_sequence: 3,
	type: "execution_status",
	execution_id: "state-sse",
	status: "running",
	current_node_id: "build",
	updated_at: 1_759_000_000_100,
};

interface Harness {
	frames: ExecutionStreamFrame[];
	gaps: StreamGap[];
	states: StreamState[];
}

function connect(
	options: { token?: string | null; afterSequence?: number | null } = {},
): { stream: ReturnType<typeof createExecutionStream>; seen: Harness } {
	const seen: Harness = { frames: [], gaps: [], states: [] };
	const stream = createExecutionStream({
		executionId: "step-sse",
		baseUrl: "http://127.0.0.1:5003",
		token: options.token ?? null,
		afterSequence: options.afterSequence ?? null,
		handlers: {
			onFrame: (frame) => seen.frames.push(frame),
			onGap: (streamGap) => seen.gaps.push(streamGap),
			onState: (state) => seen.states.push(state),
		},
	});
	return { stream, seen };
}

beforeEach(() => {
	FakeEventSource.reset();
	vi.stubGlobal("EventSource", FakeEventSource);
	vi.useFakeTimers();
});

afterEach(() => {
	vi.useRealTimers();
	vi.unstubAllGlobals();
});

// ─── URL building ───────────────────────────────────────────────────────────

describe("buildExecutionStreamUrl", () => {
	it("targets the execution events route under the API prefix", () => {
		expect(buildExecutionStreamUrl("http://127.0.0.1:5003", "step-1")).toBe(
			"http://127.0.0.1:5003/api/v1/executions/step-1/events",
		);
	});

	it("tolerates a trailing slash and encodes the execution id", () => {
		expect(buildExecutionStreamUrl("http://127.0.0.1:5003/", "step/one")).toBe(
			"http://127.0.0.1:5003/api/v1/executions/step%2Fone/events",
		);
	});

	it("resumes with after_sequence and authenticates with token", () => {
		const url = buildExecutionStreamUrl("http://127.0.0.1:5003", "step-1", {
			afterSequence: 41,
			token: "s3cret",
		});
		expect(url).toBe(
			"http://127.0.0.1:5003/api/v1/executions/step-1/events?after_sequence=41&token=s3cret",
		);
	});

	it("resumes from sequence 0 without dropping the cursor parameter", () => {
		expect(
			buildExecutionStreamUrl("http://127.0.0.1:5003", "step-1", {
				afterSequence: 0,
			}),
		).toContain("after_sequence=0");
	});
});

describe("redactStreamUrl", () => {
	it("hides the token but keeps the rest of the query", () => {
		const redacted = redactStreamUrl(
			"http://127.0.0.1:5003/api/v1/executions/step-1/events?after_sequence=41&token=s3cret",
		);
		expect(redacted).not.toContain("s3cret");
		expect(redacted).toContain("token=REDACTED");
		expect(redacted).toContain("after_sequence=41");
	});

	it("leaves a tokenless URL untouched", () => {
		const url = "http://127.0.0.1:5003/api/v1/executions/step-1/events";
		expect(redactStreamUrl(url)).toBe(url);
	});
});

// ─── Frame parsing ──────────────────────────────────────────────────────────

describe("parseStreamFrame", () => {
	it("decodes the opening frame", () => {
		expect(parseStreamFrame("stream_opened", JSON.stringify(OPENED))).toEqual({
			type: "stream_opened",
			execution_id: "step-sse",
			latest_sequence: 0,
		});
	});

	it("decodes a session_log frame into its row", () => {
		const frame = parseStreamFrame(
			"session_log",
			JSON.stringify(SESSION_LOG_FRAME),
		);
		expect(frame).toEqual({
			type: "session_log",
			event_sequence: 1,
			execution_id: "step-sse",
			log: {
				id: "log-1",
				step_execution_id: "step-sse",
				task_id: "task-sse",
				event_type: "text",
				payload: "e2e-hello",
				sequence: 1,
				created_at: 1_759_000_000_000,
			},
		});
	});

	it("decodes a step_status frame", () => {
		expect(
			parseStreamFrame("step_status", JSON.stringify(STEP_STATUS_FRAME)),
		).toMatchObject({
			type: "step_status",
			event_sequence: 2,
			execution_id: "step-sse",
			node_id: "build",
			status: "in_progress",
			output: null,
			completed_at: null,
		});
	});

	it("decodes an execution_status frame", () => {
		expect(
			parseStreamFrame(
				"execution_status",
				JSON.stringify(EXECUTION_STATUS_FRAME),
			),
		).toMatchObject({
			type: "execution_status",
			event_sequence: 3,
			execution_id: "state-sse",
			status: "running",
			current_node_id: "build",
		});
	});

	it("falls back to data.type when the SSE event name is missing", () => {
		const frame = parseStreamFrame("", JSON.stringify(SESSION_LOG_FRAME));
		expect(frame?.type).toBe("session_log");
	});

	it("ignores heartbeats, unknown kinds and malformed payloads", () => {
		expect(parseStreamFrame("keep_alive", "")).toBeNull();
		expect(parseStreamFrame("keep_alive", " ")).toBeNull();
		expect(parseStreamFrame("mystery", JSON.stringify({ a: 1 }))).toBeNull();
		expect(parseStreamFrame("session_log", "{not json")).toBeNull();
		// A kind frame without the cursor cannot be ordered, so it is dropped.
		expect(
			parseStreamFrame("step_status", JSON.stringify({ node_id: "build" })),
		).toBeNull();
	});
});

// ─── Connection behaviour ───────────────────────────────────────────────────

describe("execution stream", () => {
	it("delivers the opening frame and every event kind in sequence order", () => {
		const { stream, seen } = connect();
		stream.start();

		expect(seen.states).toEqual(["connecting"]);
		expect(stream.state()).toBe("connecting");
		expect(stream.lastSequence()).toBeNull();

		FakeEventSource.latest.emit("stream_opened", OPENED);
		FakeEventSource.latest.emit("session_log", SESSION_LOG_FRAME);
		FakeEventSource.latest.emit("step_status", STEP_STATUS_FRAME);
		FakeEventSource.latest.emit("keep_alive", "");

		expect(stream.state()).toBe("open");
		expect(stream.lastSequence()).toBe(2);
		expect(seen.frames.map((frame) => frame.type)).toEqual([
			"stream_opened",
			"session_log",
			"step_status",
		]);
		expect(seen.gaps).toEqual([]);
		stream.close();
	});

	it("drops duplicates from the resumed replay and reports a cursor jump", () => {
		const { stream, seen } = connect();
		stream.start();
		FakeEventSource.latest.emit("stream_opened", OPENED);
		FakeEventSource.latest.emit("session_log", SESSION_LOG_FRAME);
		// 1 again: the overlap a resume can produce. Dropped, not re-delivered.
		FakeEventSource.latest.emit("session_log", SESSION_LOG_FRAME);
		expect(seen.frames).toHaveLength(2);

		// 5 skips 2..4: the buffer no longer covers the range.
		FakeEventSource.latest.emit("step_status", {
			...STEP_STATUS_FRAME,
			event_sequence: 5,
		});
		expect(seen.gaps).toEqual([
			{ reason: "sequence_gap", expected_sequence: 2, received_sequence: 5 },
		]);
		expect(seen.frames).toHaveLength(3);
		expect(stream.lastSequence()).toBe(5);
		stream.close();
	});

	it("reconnects with backoff, resuming from the last observed sequence", async () => {
		const { stream, seen } = connect();
		stream.start();
		FakeEventSource.latest.emit("stream_opened", OPENED);
		FakeEventSource.latest.emit("session_log", SESSION_LOG_FRAME);

		FakeEventSource.latest.fail();
		expect(FakeEventSource.latest.closed).toBe(true);
		expect(stream.state()).toBe("reconnecting");

		// First retry after the initial backoff, not immediately.
		await vi.advanceTimersByTimeAsync(DEFAULT_BACKOFF.initialMs);
		expect(FakeEventSource.instances).toHaveLength(2);
		expect(FakeEventSource.latest.url).toContain("after_sequence=1");

		// The engine replays above the cursor and continues live.
		FakeEventSource.latest.emit("stream_opened", {
			execution_id: "step-sse",
			latest_sequence: 4,
		});
		expect(stream.state()).toBe("open");
		expect(seen.gaps).toEqual([
			{ reason: "reconnect", expected_sequence: 2, received_sequence: 4 },
		]);

		FakeEventSource.latest.emit("step_status", {
			...STEP_STATUS_FRAME,
			event_sequence: 2,
		});
		expect(stream.lastSequence()).toBe(2);
		const last = seen.frames[seen.frames.length - 1];
		expect(last?.type).toBe("step_status");
		stream.close();
	});

	it("backs off exponentially and caps the delay", async () => {
		expect(backoffDelay(1)).toBe(1000);
		expect(backoffDelay(2)).toBe(2000);
		expect(backoffDelay(3)).toBe(4000);
		expect(backoffDelay(99)).toBe(DEFAULT_BACKOFF.maxMs);

		const { stream } = connect();
		stream.start();
		FakeEventSource.latest.emit("stream_opened", OPENED);

		// Each failed attempt waits longer than the previous one.
		FakeEventSource.latest.fail();
		await vi.advanceTimersByTimeAsync(999);
		expect(FakeEventSource.instances).toHaveLength(1);
		await vi.advanceTimersByTimeAsync(1);
		expect(FakeEventSource.instances).toHaveLength(2);

		FakeEventSource.latest.fail();
		await vi.advanceTimersByTimeAsync(1999);
		expect(FakeEventSource.instances).toHaveLength(2);
		await vi.advanceTimersByTimeAsync(1);
		expect(FakeEventSource.instances).toHaveLength(3);
		stream.close();
	});

	it("reports a restart and replays from scratch when the cursor resets", async () => {
		const { stream, seen } = connect();
		stream.start();
		FakeEventSource.latest.emit("stream_opened", OPENED);
		FakeEventSource.latest.emit("session_log", SESSION_LOG_FRAME);
		FakeEventSource.latest.emit("step_status", {
			...STEP_STATUS_FRAME,
			event_sequence: 7,
		});
		expect(stream.lastSequence()).toBe(7);

		// Engine restarted: a fresh registry reports a lower cursor.
		FakeEventSource.latest.fail();
		await vi.advanceTimersByTimeAsync(DEFAULT_BACKOFF.initialMs);
		FakeEventSource.latest.emit("stream_opened", {
			execution_id: "step-sse",
			latest_sequence: 0,
		});

		expect(seen.gaps).toEqual([
			{
				reason: "sequence_gap",
				expected_sequence: 2,
				received_sequence: 7,
			},
			{ reason: "restart", expected_sequence: null, received_sequence: 0 },
		]);

		// The stale cursor is dropped: the next connection starts from scratch
		// and the replayed frames are delivered again (the store dedupes rows).
		await vi.advanceTimersByTimeAsync(0);
		expect(FakeEventSource.instances).toHaveLength(3);
		expect(FakeEventSource.latest.url).not.toContain("after_sequence");
		FakeEventSource.latest.emit("stream_opened", {
			execution_id: "step-sse",
			latest_sequence: 0,
		});
		// The restart gap is reported once; the follow-up open is not a second
		// outage.
		expect(seen.gaps).toHaveLength(2);
		expect(stream.state()).toBe("open");
		stream.close();
	});

	it("resumes from an explicit cursor and stops after close", async () => {
		const { stream } = connect({ afterSequence: 12 });
		stream.start();
		expect(FakeEventSource.latest.url).toContain("after_sequence=12");
		expect(stream.lastSequence()).toBe(12);

		FakeEventSource.latest.fail();
		await vi.advanceTimersByTimeAsync(DEFAULT_BACKOFF.initialMs);
		expect(FakeEventSource.latest.url).toContain("after_sequence=12");

		stream.close();
		expect(stream.state()).toBe("closed");
		const opened = FakeEventSource.instances.length;
		FakeEventSource.latest.fail();
		await vi.advanceTimersByTimeAsync(DEFAULT_BACKOFF.maxMs * 2);
		expect(FakeEventSource.instances).toHaveLength(opened);
	});

	it("never logs the token and hands out only a redacted URL", () => {
		const spies = [
			vi.spyOn(console, "log").mockImplementation(() => {}),
			vi.spyOn(console, "info").mockImplementation(() => {}),
			vi.spyOn(console, "warn").mockImplementation(() => {}),
			vi.spyOn(console, "error").mockImplementation(() => {}),
			vi.spyOn(console, "debug").mockImplementation(() => {}),
		];
		const { stream } = connect({ token: "s3cret" });
		stream.start();
		FakeEventSource.latest.emit("stream_opened", OPENED);
		FakeEventSource.latest.emit("session_log", SESSION_LOG_FRAME);
		FakeEventSource.latest.fail();

		// The token is transmitted (EventSource cannot send headers)…
		expect(FakeEventSource.latest.url).toContain("token=s3cret");
		// …but never rendered: the only URL this client hands out is redacted.
		expect(stream.redactedUrl()).not.toContain("s3cret");
		expect(stream.redactedUrl()).toContain("token=REDACTED");

		for (const spy of spies) {
			for (const call of spy.mock.calls) {
				expect(JSON.stringify(call)).not.toContain("s3cret");
			}
			spy.mockRestore();
		}
		stream.close();
	});
});
