// F6 acceptance tests for wire-format normalization (executions-api).
//
// Verifies the C8 → canonical shape translation that drives the history table
// and the session log renderer through the public API surface:
//   - a completed flow yields one Execution row per step with correct
//     tokens/cost/duration/timestamps;
//   - tool_use events carry tool_name + tool_input, tool_result events carry a
//     truncated flag, usage events carry token counts;
//   - list endpoints receive `limit` + `before_sequence` paging params.
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./api", () => ({
	api: { get: vi.fn() },
}));

import { api } from "./api";
import {
	computeAggregate,
	getSessionLog,
	listExecutions,
	normalizeExecution,
	normalizeSessionEvent,
} from "./executions-api";
import type { Execution } from "./types";

const getMock = api.get as ReturnType<typeof vi.fn>;

beforeEach(() => {
	getMock.mockReset();
});

/** Raw C8 step-execution wire row. */
function stepRaw(
	overrides: Record<string, unknown> = {},
): Record<string, unknown> {
	return {
		id: "step-1",
		flow_instance_id: "flow-1",
		execution_state_id: "exec-1",
		node_id: "build",
		task_id: "task-1",
		status: "completed",
		model: "claude-sonnet-4",
		input_tokens: 1500,
		output_tokens: 300,
		cost: 0.0412,
		duration_ms: 8120,
		created_at: 1_751_234_567,
		completed_at: 1_751_242_687,
		sequence: 2,
		...overrides,
	};
}

/** Raw C8 session-log wire row (event_type + string JSON payload). */
function eventRaw(
	eventType: string,
	payload: unknown,
	overrides: Record<string, unknown> = {},
): Record<string, unknown> {
	return {
		id: "log-1",
		step_execution_id: "exec-1",
		task_id: "task-1",
		event_type: eventType,
		payload: typeof payload === "string" ? payload : JSON.stringify(payload),
		sequence: 1,
		created_at: 1_751_234_567,
		...overrides,
	};
}

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

describe("normalizeExecution", () => {
	it("maps one step row to one execution row with metrics and ISO timestamps", () => {
		const execution = normalizeExecution(stepRaw());
		expect(execution.id).toBe("step-1");
		expect(execution.task_id).toBe("task-1");
		expect(execution.node_id).toBe("build");
		expect(execution.status).toBe("completed");
		expect(execution.model).toBe("claude-sonnet-4");
		expect(execution.input_tokens).toBe(1500);
		expect(execution.output_tokens).toBe(300);
		expect(execution.cost).toBe(0.0412);
		expect(execution.duration_ms).toBe(8120);
		// Unix seconds → ISO strings for the timestamps columns.
		expect(execution.started_at).toBe(
			new Date(1_751_234_567_000).toISOString(),
		);
		expect(execution.completed_at).toBe(
			new Date(1_751_242_687_000).toISOString(),
		);
		expect(execution.sequence).toBe(2);
	});

	it("keeps the paging cursor when the wire row carries a sequence", () => {
		expect(normalizeExecution(stepRaw({ sequence: 41 })).sequence).toBe(41);
	});
});

describe("listExecutions — one row per step with correct totals", () => {
	it("returns one row per step with correct token/cost totals for a completed flow", async () => {
		getMock.mockResolvedValue({
			executions: [
				stepRaw({
					id: "step-a",
					input_tokens: 1500,
					output_tokens: 300,
					cost: 0.0412,
					duration_ms: 8120,
					sequence: 2,
				}),
				stepRaw({
					id: "step-b",
					input_tokens: 1200,
					output_tokens: 220,
					cost: 0.022,
					duration_ms: 5330,
					sequence: 1,
				}),
			],
			has_more: false,
		});

		const res = await listExecutions("task-1", 50);
		expect(res.executions.map((execution) => execution.id)).toEqual([
			"step-a",
			"step-b",
		]);
		expect(res.executions[0]).toMatchObject({
			node_id: "build",
			status: "completed",
			model: "claude-sonnet-4",
			input_tokens: 1500,
			output_tokens: 300,
			cost: 0.0412,
			duration_ms: 8120,
		});
		expect(res.aggregate).toEqual({
			total_input_tokens: 2700,
			total_output_tokens: 520,
			total_cost: 0.0632,
			total_duration_ms: 13450,
		});
		expect(res.has_more).toBe(false);
	});

	it("accepts a bare array payload and infers has_more from the page size", async () => {
		getMock.mockResolvedValue([stepRaw()]);
		const res = await listExecutions("task-1", 1);
		expect(res.executions).toHaveLength(1);
		expect(res.has_more).toBe(true);
	});
});

describe("computeAggregate", () => {
	it("sums tokens, cost and duration across rows", () => {
		const agg = computeAggregate([
			execRow(2, {
				input_tokens: 1500,
				output_tokens: 300,
				cost: 0.0412,
				duration_ms: 8120,
			}),
			execRow(1, {
				input_tokens: 1200,
				output_tokens: 220,
				cost: 0.022,
				duration_ms: 5330,
			}),
		]);
		expect(agg).toEqual({
			total_input_tokens: 2700,
			total_output_tokens: 520,
			total_cost: 0.0632,
			total_duration_ms: 13450,
		});
	});
});

describe("normalizeSessionEvent", () => {
	it("renders tool_use with tool_name and tool_input", () => {
		const event = normalizeSessionEvent(
			eventRaw("tool_use", {
				tool_name: "read",
				tool_input: { path: "src/lib/types.ts" },
			}),
		);
		expect(event.kind).toBe("tool_use");
		expect(event.data).toMatchObject({
			tool_name: "read",
			tool_input: { path: "src/lib/types.ts" },
		});
	});

	it("renders tool_result with a truncated flag and string payload JSON", () => {
		const event = normalizeSessionEvent(
			eventRaw(
				"tool_result",
				JSON.stringify({
					tool_name: "bash",
					output: "line 1\nline 2",
					truncated: true,
				}),
			),
		);
		expect(event.kind).toBe("tool_result");
		expect(event.data).toMatchObject({
			tool_name: "bash",
			output: "line 1\nline 2",
			truncated: true,
		});
	});

	it("renders usage with token counts", () => {
		const event = normalizeSessionEvent(
			eventRaw("usage", { input_tokens: 9876, output_tokens: 4321 }),
		);
		expect(event.kind).toBe("usage");
		expect(event.data).toEqual({ input_tokens: 9876, output_tokens: 4321 });
	});

	it("renders text, outcome and error kinds", () => {
		const text = normalizeSessionEvent(eventRaw("text", { content: "hello" }));
		expect(text.kind).toBe("text");
		expect(text.data).toEqual({ content: "hello" });

		const outcome = normalizeSessionEvent(
			eventRaw("outcome", { success: true, result: "done" }),
		);
		expect(outcome.kind).toBe("outcome");
		expect((outcome as { data: { success: boolean } }).data.success).toBe(true);

		const error = normalizeSessionEvent(
			eventRaw("error", { error_type: "decode", message: "boom" }),
		);
		expect(error.kind).toBe("error");
		expect(error.data).toMatchObject({ error_type: "decode", message: "boom" });
	});

	it("normalises the timestamp to ISO and falls back to text for unknown kinds", () => {
		const known = normalizeSessionEvent(
			eventRaw("usage", { input_tokens: 1, output_tokens: 2 }),
		);
		expect(known.timestamp).toBe(new Date(1_751_234_567_000).toISOString());
		expect(known.execution_id).toBe("exec-1");
		expect(known.sequence).toBe(1);

		const unknown = normalizeSessionEvent(
			eventRaw("assistant", { content: "hi" }),
		);
		expect(unknown.kind).toBe("text");
	});
});

describe("getSessionLog", () => {
	it("decodes events from a wrapped payload and surfaces has_more", async () => {
		getMock.mockResolvedValue({
			events: [
				eventRaw("text", { content: "a" }),
				eventRaw("text", { content: "b" }),
			],
			has_more: true,
		});
		const res = await getSessionLog("exec-1", 100);
		expect(res.events).toHaveLength(2);
		expect(res.events[0].kind).toBe("text");
		expect(res.has_more).toBe(true);
	});
});

describe("paging query params", () => {
	it("listExecutions sends limit and before_sequence on older pages", async () => {
		getMock.mockResolvedValue({ executions: [], has_more: false });
		await listExecutions("task-1", 50, 71);
		expect(getMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task-1/executions?limit=50&before_sequence=71",
		);
	});

	it("listExecutions omits before_sequence on the first page", async () => {
		getMock.mockResolvedValue({ executions: [], has_more: false });
		await listExecutions("task-1");
		expect(getMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task-1/executions?limit=50",
		);
	});

	it("getSessionLog sends limit and before_sequence on older pages", async () => {
		getMock.mockResolvedValue({ events: [], has_more: false });
		await getSessionLog("exec-1", 100, 101);
		expect(getMock).toHaveBeenCalledWith(
			"/api/v1/executions/exec-1/logs?limit=100&before_sequence=101",
		);
	});
});
