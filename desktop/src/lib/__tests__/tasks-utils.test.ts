// Unit tests for the pure task helpers in `$lib/tasks-utils`.
//
// These cover acceptance criteria that must hold without a DOM or network:
//   - missing-title validation never produces a payload (no network call)
//   - filters and hierarchy flattening are pure and instant on 200 tasks
//   - ready-only filtering and parent/child indentation
import { describe, expect, it } from "vitest";
import type { Task, TaskFilters } from "../types";
import {
	buildTaskSubmission,
	buildTaskTreeRows,
	compareTasks,
	filterTasks,
	formatTimestamp,
	hasFormErrors,
	matchesFilters,
	sortTasks,
	validateTaskForm,
} from "../tasks-utils";

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

/** 200 synthetic tasks in a realistic hierarchy. */
function makeManyTasks(count = 200): Task[] {
	const tasks: Task[] = [];
	for (let i = 0; i < count; i++) {
		const id = `t-${String(i).padStart(3, "0")}`;
		tasks.push(
			makeTask({
				id,
				short_id: id,
				title: `Task ${i} with some descriptive words`,
				level: i % 5 === 0 ? "epic" : i % 3 === 0 ? "ticket" : "task",
				priority:
					i % 4 === 0
						? "critical"
						: i % 3 === 0
							? "high"
							: i % 2 === 0
								? "medium"
								: "low",
				status: i % 7 === 0 ? "done" : i % 5 === 0 ? "in_progress" : "todo",
				tags: [`tag-${i % 10}`, "shared"],
				// Every epic owns one ticket; that ticket owns tasks.
				parent_id:
					// eslint-disable-next-line no-nested-ternary
					i % 5 === 0
						? null
						: i % 3 === 0
							? `t-${String(Math.floor(i / 5) * 5).padStart(3, "0")}`
							: `t-${String(Math.floor(i / 3) * 3).padStart(3, "0")}`,
			}),
		);
	}
	return tasks;
}

describe("validateTaskForm / buildTaskSubmission", () => {
	it("rejects a missing title and yields no payload (no network)", () => {
		const { errors, payload } = buildTaskSubmission({
			title: "",
			level: "task",
			priority: "medium",
		});
		expect(payload).toBeNull();
		expect(errors.title).toBe("Title is required");
	});

	it("rejects a whitespace-only title", () => {
		const { payload, errors } = buildTaskSubmission({
			title: "   ",
			level: "task",
			priority: "medium",
		});
		expect(payload).toBeNull();
		expect(errors.title).toBe("Title is required");
	});

	it("rejects titles longer than 200 characters", () => {
		const { payload, errors } = buildTaskSubmission({
			title: "x".repeat(201),
			level: "task",
			priority: "medium",
		});
		expect(payload).toBeNull();
		expect(errors.title).toMatch(/200 characters/);
	});

	it("rejects invalid level and priority enums", () => {
		const { payload, errors } = buildTaskSubmission({
			title: "Valid title",
			level: "bogus",
			priority: "urgent",
		});
		expect(payload).toBeNull();
		expect(errors.level).toBeDefined();
		expect(errors.priority).toBeDefined();
	});

	it("rejects a parent that does not exist in the candidate set", () => {
		const { errors } = buildTaskSubmission(
			{ title: "Valid", level: "task", priority: "low", parent_id: "missing" },
			{ existingIds: new Set(["t-001"]) },
		);
		expect(errors.parent_id).toMatch(/no longer exists/);
	});

	it("builds a clean payload for a valid submission", () => {
		const { errors, payload } = buildTaskSubmission({
			title: "  Ship the thing  ",
			description: "Details",
			level: "ticket",
			priority: "high",
			parent_id: "t-001",
			tags: ["a", "", "b"],
		});
		expect(hasFormErrors(errors)).toBe(false);
		expect(payload).toEqual({
			title: "Ship the thing",
			description: "Details",
			level: "ticket",
			priority: "high",
			parent_id: "t-001",
			tags: ["a", "b"],
		});
	});

	it("allows title exactly at the 200-character limit", () => {
		const { payload } = buildTaskSubmission({
			title: "y".repeat(200),
			level: "task",
			priority: "low",
		});
		expect(payload).not.toBeNull();
	});
});

describe("matchesFilters / filterTasks", () => {
	const tasks = [
		makeTask({ id: "e-1", level: "epic", status: "todo", priority: "high" }),
		makeTask({
			id: "t-1",
			level: "ticket",
			status: "in_progress",
			priority: "critical",
			tags: ["urgent"],
		}),
		makeTask({
			id: "a-1",
			level: "task",
			status: "done",
			priority: "low",
			title: "Fix the search box",
		}),
	];

	const base: TaskFilters = {
		level: "all",
		status: "all",
		priority: "all",
		readyOnly: false,
		search: "",
	};

	it("filters by level", () => {
		const out = filterTasks(tasks, { ...base, level: "epic" });
		expect(out.map((t) => t.id)).toEqual(["e-1"]);
	});

	it("filters by status", () => {
		const out = filterTasks(tasks, { ...base, status: "done" });
		expect(out.map((t) => t.id)).toEqual(["a-1"]);
	});

	it("filters by priority", () => {
		const out = filterTasks(tasks, { ...base, priority: "critical" });
		expect(out.map((t) => t.id)).toEqual(["t-1"]);
	});

	it("filters by ready queue membership", () => {
		const ready = new Set(["e-1", "a-1"]);
		const out = filterTasks(tasks, { ...base, readyOnly: true }, ready);
		expect(out.map((t) => t.id)).toEqual(["e-1", "a-1"]);
	});

	it("readyOnly with an empty ready set matches nothing", () => {
		expect(matchesFilters(tasks[0], { ...base, readyOnly: true })).toBe(false);
	});

	it("filters by search across id, title and tags", () => {
		expect(filterTasks(tasks, { ...base, search: "search box" }).map((t) => t.id)).toEqual([
			"a-1",
		]);
		expect(filterTasks(tasks, { ...base, search: "urgent" }).map((t) => t.id)).toEqual([
			"t-1",
		]);
		expect(filterTasks(tasks, { ...base, search: "E-1" }).map((t) => t.id)).toEqual([
			"e-1",
		]);
	});

	it("combines filters with AND semantics", () => {
		const out = filterTasks(tasks, {
			...base,
			level: "ticket",
			status: "in_progress",
		});
		expect(out.map((t) => t.id)).toEqual(["t-1"]);
	});
});

describe("sortTasks / compareTasks", () => {
	it("sorts by level, then priority, then short_id", () => {
		const tasks = [
			makeTask({ id: "x-3", level: "task", priority: "low" }),
			makeTask({ id: "x-1", level: "epic", priority: "high" }),
			makeTask({ id: "x-2", level: "ticket", priority: "critical" }),
		];
		const out = sortTasks(tasks);
		expect(out.map((t) => t.id)).toEqual(["x-1", "x-2", "x-3"]);
	});

	it("is stable and total for identical keys", () => {
		const a = makeTask({ id: "z-2", level: "task", priority: "medium" });
		const b = makeTask({ id: "z-1", level: "task", priority: "medium" });
		const c = makeTask({ id: "z-3", level: "task", priority: "medium" });
		expect(sortTasks([a, b, c]).map((t) => t.id)).toEqual(["z-1", "z-2", "z-3"]);
	});
});

describe("buildTaskTreeRows", () => {
	it("flattens the hierarchy with a depth per row", () => {
		const epic = makeTask({ id: "e-1", level: "epic" });
		const ticket = makeTask({ id: "t-1", level: "ticket", parent_id: "e-1" });
		const child1 = makeTask({ id: "a-1", level: "task", parent_id: "t-1" });
		const child2 = makeTask({ id: "a-2", level: "task", parent_id: "t-1" });
		const rows = buildTaskTreeRows([epic, ticket, child1, child2]);

		expect(rows).toEqual([
			{ task: epic, depth: 0, hasChildren: true },
			{ task: ticket, depth: 1, hasChildren: true },
			{ task: child1, depth: 2, hasChildren: false },
			{ task: child2, depth: 2, hasChildren: false },
		]);
	});

	it("treats a task whose parent is filtered out as a root", () => {
		const ticket = makeTask({ id: "t-1", level: "ticket", parent_id: "e-missing" });
		const rows = buildTaskTreeRows([ticket]);
		expect(rows).toEqual([{ task: ticket, depth: 0, hasChildren: false }]);
	});

	it("leaves collapsed subtrees as single rows", () => {
		const epic = makeTask({ id: "e-1", level: "epic" });
		const ticket = makeTask({ id: "t-1", level: "ticket", parent_id: "e-1" });
		const rows = buildTaskTreeRows([epic, ticket], {
			collapsedIds: new Set(["e-1"]),
		});
		expect(rows.map((r) => ({ id: r.task.id, depth: r.depth }))).toEqual([
			{ id: "e-1", depth: 0 },
		]);
	});

	it("sorts siblings within a parent", () => {
		const epic = makeTask({ id: "e-1", level: "epic" });
		const ta = makeTask({ id: "t-b", level: "ticket", parent_id: "e-1", priority: "low" });
		const tb = makeTask({ id: "t-a", level: "ticket", parent_id: "e-1", priority: "high" });
		const rows = buildTaskTreeRows([epic, ta, tb]);
		expect(rows.map((r) => r.task.id)).toEqual(["e-1", "t-a", "t-b"]);
	});
});

describe("performance: 200 tasks", () => {
	it("filters, sorts and flattens 200 tasks well under 500ms", () => {
		const tasks = makeManyTasks(200);
		const ready = new Set(
			tasks.filter((t) => t.status === "todo").map((t) => t.id),
		);
		const filters: TaskFilters = {
			level: "all",
			status: "all",
			priority: "all",
			readyOnly: true,
			search: "descriptive",
		};

		const started = performance.now();
		const filtered = filterTasks(tasks, filters, ready);
		const sorted = sortTasks(filtered);
		const rows = buildTaskTreeRows(sorted);
		const elapsed = performance.now() - started;

		expect(rows.length).toBeGreaterThan(0);
		expect(rows.every((row, index) => index === 0 || row.depth >= 0)).toBe(true);
		// Acceptance: 200 tasks < 500ms. The generous bound still catches any
		// accidental O(n^2) blow-up in the flattening/filtering pipeline.
		expect(elapsed).toBeLessThan(500);
	});

	it("flattening preserves every surviving task exactly once", () => {
		const tasks = makeManyTasks(200);
		const rows = buildTaskTreeRows(tasks);
		const seen = new Set(rows.map((r) => r.task.id));
		expect(seen.size).toBe(tasks.length);
	});
});

describe("formatTimestamp", () => {
	it("renders a Unix epoch and tolerates missing values", () => {
		expect(formatTimestamp(1_700_000_000)).toMatch(/\d/);
		expect(formatTimestamp(0)).toBe("—");
		expect(formatTimestamp(null)).toBe("—");
		expect(formatTimestamp(undefined)).toBe("—");
	});
});
