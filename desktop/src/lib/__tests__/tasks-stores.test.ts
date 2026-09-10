// Store tests for `$stores/tasks`: optimistic mutations with rollback.
//
// The api layer (`$lib/tasks-api`) is fully mocked so these tests verify the
// optimistic/rollback contract and that inline errors surface the server
// message — including the C6 cycle rejection.
import { beforeEach, describe, expect, it, vi } from "vitest";
import { get } from "svelte/store";
import type { Task } from "../types";
import { defaultTaskFilters } from "../tasks-utils";

const apiMocks = vi.hoisted(() => ({
	listTasks: vi.fn(),
	listReadyTasks: vi.fn(),
	getTask: vi.fn(),
	getBlockers: vi.fn(),
	listSections: vi.fn(),
	createTask: vi.fn(),
	updateTask: vi.fn(),
	archiveTask: vi.fn(),
	addDependency: vi.fn(),
	removeDependency: vi.fn(),
}));

vi.mock("$lib/tasks-api", () => apiMocks);

import {
	archiveTaskOptimistic,
	createTaskDetailStore,
	createTaskOptimistic,
	error,
	errorMessage,
	filters,
	loading,
	loadTasks,
	mutationError,
	readyIds,
	resetFilters,
	setFilter,
	taskCount,
	taskRows,
	tasks,
	updateTaskOptimistic,
} from "$stores/tasks";

function makeTask(overrides: Partial<Task> & { id: string }): Task {
	const id = overrides.id;
	return {
		short_id: id.slice(0, 8),
		title: "Task " + id,
		description: "",
		level: "task",
		priority: "medium",
		status: "todo",
		tags: [],
		parent_id: null,
		archived: false,
		created_at: 1_700_000_000,
		updated_at: 1_700_000_000,
		...overrides,
	};
}

beforeEach(() => {
	vi.clearAllMocks();
	apiMocks.listReadyTasks.mockResolvedValue([]);
	apiMocks.listSections.mockRejectedValue(new Error("not found"));
	tasks.set([]);
	readyIds.set(new Set());
	filters.set(defaultTaskFilters());
	loading.set(false);
	error.set(null);
	mutationError.set(null);
});

describe("errorMessage", () => {
	it("prefers the ApiError message field", () => {
		expect(
			errorMessage({
				message: "Adding this dependency would create a cycle",
				status: 400,
			}),
		).toBe("Adding this dependency would create a cycle");
	});

	it("falls back to an Error's message, then a generic string", () => {
		expect(errorMessage(new Error("boom"))).toBe("boom");
		expect(errorMessage({ nope: true })).toBe("Something went wrong");
	});
});

describe("list store", () => {
	it("loads tasks and ready ids", async () => {
		const loaded = [makeTask({ id: "t-1" }), makeTask({ id: "t-2" })];
		apiMocks.listTasks.mockResolvedValue(loaded);
		apiMocks.listReadyTasks.mockResolvedValue([loaded[0]]);

		await loadTasks();

		expect(get(tasks)).toEqual(loaded);
		expect(get(readyIds).has("t-1")).toBe(true);
		expect(get(readyIds).has("t-2")).toBe(false);
		expect(get(loading)).toBe(false);
	});

	it("sets an inline error when the list request fails", async () => {
		apiMocks.listTasks.mockRejectedValue({
			message: "Crystalline is not connected yet",
			status: 0,
		});

		await loadTasks();
		expect(get(error)).toBe("Crystalline is not connected yet");
		expect(get(tasks)).toEqual([]);
	});
});

describe("createTaskOptimistic", () => {
	it("inserts a phantom row, then replaces it with the server task", async () => {
		const created = makeTask({ id: "t-new", level: "epic" });
		apiMocks.createTask.mockResolvedValue(created);

		const promise = createTaskOptimistic({
			title: "New task",
			level: "epic",
			priority: "high",
		});
		// Phantom present before the request settles.
		expect(get(tasks).length).toBe(1);
		expect(get(tasks)[0].id).toMatch(/^temp-/);

		await promise;
		expect(get(tasks)).toEqual([created]);
		expect(get(readyIds).has("t-new")).toBe(true);
	});

	it("rolls back the phantom row and surfaces the error on failure", async () => {
		apiMocks.createTask.mockRejectedValue({
			message: "Title is required",
			status: 400,
		});

		await expect(
			createTaskOptimistic({ title: "", level: "task", priority: "low" }),
		).rejects.toBeTruthy();
		expect(get(tasks)).toEqual([]);
		expect(get(mutationError)).toBe("Title is required");
	});
});

describe("updateTaskOptimistic", () => {
	it("applies the patch optimistically and replaces with the server task", async () => {
		const original = makeTask({ id: "t-1", status: "todo" });
		const updated = makeTask({ id: "t-1", status: "done" });
		tasks.set([original]);
		apiMocks.updateTask.mockResolvedValue(updated);

		const promise = updateTaskOptimistic("t-1", { status: "done" });
		expect(get(tasks)[0].status).toBe("done"); // optimistic

		await promise;
		expect(get(tasks)[0]).toEqual(updated);
		// Done tasks leave the ready queue.
		expect(get(readyIds).has("t-1")).toBe(false);
	});

	it("restores the previous value and surfaces the error on failure", async () => {
		const original = makeTask({ id: "t-1", status: "todo" });
		tasks.set([original]);
		apiMocks.updateTask.mockRejectedValue({
			message: "Something broke upstream",
			status: 500,
		});

		await expect(
			updateTaskOptimistic("t-1", { status: "done" }),
		).rejects.toBeTruthy();
		expect(get(tasks)[0]).toEqual(original);
		expect(get(mutationError)).toBe("Something broke upstream");
	});
});

describe("archiveTaskOptimistic", () => {
	it("removes the task locally and on failure restores the whole list", async () => {
		const a = makeTask({ id: "t-1" });
		const b = makeTask({ id: "t-2" });
		tasks.set([a, b]);
		apiMocks.archiveTask.mockResolvedValue(undefined);

		await archiveTaskOptimistic("t-1");
		expect(get(tasks).map((t) => t.id)).toEqual(["t-2"]);

		apiMocks.archiveTask.mockRejectedValue({
			message: "Archive failed",
			status: 500,
		});
		tasks.set([a, b]);
		await expect(archiveTaskOptimistic("t-1")).rejects.toBeTruthy();
		expect(get(tasks).map((t) => t.id)).toEqual(["t-1", "t-2"]);
		expect(get(mutationError)).toBe("Archive failed");
	});
});

describe("filters are instant and local", () => {
	it("recomputes rows without touching the network", async () => {
		const a = makeTask({ id: "e-1", level: "epic", status: "todo" });
		const b = makeTask({ id: "t-1", level: "ticket", status: "done" });
		apiMocks.listTasks.mockResolvedValue([a, b]);
		await loadTasks();

		const callsAfterLoad = apiMocks.listTasks.mock.calls.length;
		setFilter("level", "epic");
		setFilter("status", "done");
		setFilter("search", "nope");

		expect(get(taskRows).length).toBe(0); // nothing matches
		// No additional requests were issued for any filter change.
		expect(apiMocks.listTasks.mock.calls.length).toBe(callsAfterLoad);
		expect(get(taskCount)).toBe(2);

		resetFilters();
		expect(get(filters).level).toBe("all");
		expect(get(taskRows).length).toBe(2);
	});
});

describe("detail store", () => {
	it("loads the task and marks 404 tasks", async () => {
		apiMocks.getTask.mockRejectedValue({
			message: "Task not found",
			status: 404,
		});
		const detail = createTaskDetailStore("missing");
		await detail.ready;
		expect(get(detail).notFound).toBe(true);
		expect(get(detail).task).toBeNull();
	});

	it("rolls back an inline status update and surfaces the server message", async () => {
		const original = makeTask({ id: "t-1", status: "todo" });
		tasks.set([original]);
		apiMocks.getTask.mockResolvedValue(original);
		apiMocks.getBlockers.mockResolvedValue([]);
		apiMocks.updateTask.mockRejectedValue({
			message: "Invalid transition",
			status: 409,
		});

		const detail = createTaskDetailStore("t-1");
		await detail.ready;
		expect(get(detail).task?.status).toBe("todo");

		await expect(detail.update({ status: "done" })).rejects.toBeTruthy();
		expect(get(detail).task).toEqual(original);
		expect(get(detail).mutationError).toBe("Invalid transition");
	});

	it("surfaces the cycle blocker error from C6 and rolls back the optimistic blocker", async () => {
		const a = makeTask({ id: "t-a" });
		const b = makeTask({ id: "t-b" });
		tasks.set([a, b]);
		apiMocks.getTask.mockResolvedValue(a);
		apiMocks.getBlockers.mockResolvedValue([]);
		apiMocks.addDependency.mockRejectedValue({
			message: "Adding this dependency would create a cycle",
			status: 400,
		});

		const detail = createTaskDetailStore("t-a");
		await detail.ready;
		expect(get(detail).blockers).toEqual([]);

		// Optimistic add happens immediately.
		const promise = detail.addBlocker("t-b").catch(() => {});
		expect(get(detail).blockers.map((t) => t.id)).toEqual(["t-b"]);

		await promise;
		// Rolled back, with the visible inline error.
		expect(get(detail).blockers).toEqual([]);
		expect(get(detail).mutationError).toContain("cycle");
	});

	it("removes a blocker; on failure restores the list", async () => {
		const a = makeTask({ id: "t-a" });
		const b = makeTask({ id: "t-b" });
		tasks.set([a, b]);
		apiMocks.getTask.mockResolvedValue(a);
		apiMocks.getBlockers.mockResolvedValue([b]);
		apiMocks.removeDependency.mockRejectedValue({
			message: "Failed to remove dependency",
			status: 500,
		});

		const detail = createTaskDetailStore("t-a");
		await detail.ready;
		expect(get(detail).blockers).toEqual([b]);

		const promise = detail.removeBlocker("t-b").catch(() => {});
		expect(get(detail).blockers).toEqual([]); // optimistic

		await promise;
		expect(get(detail).blockers).toEqual([b]);
		expect(get(detail).mutationError).toBe("Failed to remove dependency");
	});
});
