// F6 acceptance tests for the execution history / session log stores.
//
// Verifies the behaviour behind the acceptance criteria:
//   - a completed flow renders via one row per step with correct totals
//     (history store aggregates);
//   - polling refreshes every 3s while a step is in_progress and stops as soon
//     as every visible execution is terminal;
//   - page 2 (older) loads arrive via limit+before_sequence and are prepended
//     without duplicates, keeping a single chronological/ordering invariant.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { get } from "svelte/store";
import type { Execution, SessionEvent } from "./types";

const mocks = vi.hoisted(() => ({
	listExecutions: vi.fn(),
	listActiveExecutions: vi.fn(),
	getExecution: vi.fn(),
	getSessionLog: vi.fn(),
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

import { useExecutionHistory, useSessionLog } from "./stores";

beforeEach(() => {
	vi.resetAllMocks();
	vi.useFakeTimers();
	// The stores schedule polling via `window.setInterval`; under the node
	// environment the browser global is absent, so hand them the (faked) timer.
	vi.stubGlobal("window", {
		setInterval: globalThis.setInterval,
		clearInterval: globalThis.clearInterval,
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

describe("execution history store", () => {
	it("loads one row per completed step with correct footer totals and no polling", async () => {
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
		expect(get(store.polling)).toBe(false);
		expect(get(store.hasMore)).toBe(false);
		store.destroy();
	});

	it("polls every 3s while a step is in_progress and stops once terminal", async () => {
		mocks.listExecutions
			.mockResolvedValueOnce({
				executions: [execRow(1, { id: "live", status: "in_progress" })],
				has_more: false,
			})
			.mockResolvedValueOnce({
				executions: [execRow(1, { id: "live", status: "completed" })],
				has_more: false,
			});

		const store = useExecutionHistory("task-1");
		await store.load();

		expect(get(store.polling)).toBe(true);
		expect(mocks.listExecutions).toHaveBeenCalledTimes(1);

		await vi.advanceTimersByTimeAsync(3000);
		expect(mocks.listExecutions).toHaveBeenCalledTimes(2);
		expect(get(store.executions)[0].status).toBe("completed");
		expect(get(store.polling)).toBe(false);

		// No further refreshes after the terminal state.
		await vi.advanceTimersByTimeAsync(9000);
		expect(mocks.listExecutions).toHaveBeenCalledTimes(2);
		store.destroy();
	});

	it("prepends page 2 via before_sequence without duplicates and recomputes totals", async () => {
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
		// Newest-first invariant holds across the prepended pages.
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
	it("loads the newest page then prepends older events on loadOlder", async () => {
		mocks.getSessionLog
			.mockResolvedValueOnce({ events: eventPage(200, 101), has_more: true })
			.mockResolvedValueOnce({ events: eventPage(100, 1), has_more: false });

		const store = useSessionLog("exec-1");
		await store.init("completed");

		expect(get(store.events)).toHaveLength(100);
		expect(get(store.events)[0].sequence).toBe(101);
		expect(get(store.events)[99].sequence).toBe(200);
		expect(get(store.hasMore)).toBe(true);

		await store.loadOlder();

		expect(mocks.getSessionLog).toHaveBeenLastCalledWith("exec-1", 100, 101);
		const all = get(store.events);
		expect(all).toHaveLength(200);
		// Chronological invariant: strictly ascending sequence, no duplicates.
		expect(all[0].sequence).toBe(1);
		expect(all[199].sequence).toBe(200);
		for (let i = 1; i < all.length; i++) {
			expect(all[i].sequence).toBeGreaterThan(all[i - 1].sequence);
		}
		expect(get(store.hasMore)).toBe(false);
		store.destroy();
	});

	it("starts polling on in_progress and stops the terminal refresh on completion", async () => {
		mocks.getSessionLog.mockResolvedValue({
			events: eventPage(3, 1),
			has_more: false,
		});

		const store = useSessionLog("exec-1");
		await store.init("in_progress");
		expect(get(store.polling)).toBe(true);

		store.updateStatus("completed");
		expect(get(store.polling)).toBe(false);

		await vi.advanceTimersByTimeAsync(9000);
		expect(mocks.getSessionLog).toHaveBeenCalledTimes(1);
		store.destroy();
	});

	it("never polls when initialised with a terminal status", async () => {
		mocks.getSessionLog.mockResolvedValue({ events: [], has_more: false });
		const store = useSessionLog("exec-1");
		await store.init("completed");
		expect(get(store.polling)).toBe(false);
		store.destroy();
	});

	it("polling appends only fresh events and never duplicates", async () => {
		mocks.getSessionLog
			.mockResolvedValueOnce({ events: eventPage(5, 1), has_more: false })
			.mockResolvedValue({ events: eventPage(6, 1), has_more: false });

		const store = useSessionLog("exec-1");
		await store.init("in_progress");
		expect(get(store.events)).toHaveLength(5);

		await vi.advanceTimersByTimeAsync(3000);
		const all = get(store.events);
		expect(all).toHaveLength(6);
		expect(all.map((e) => e.sequence)).toEqual([1, 2, 3, 4, 5, 6]);
		store.destroy();
	});
});
