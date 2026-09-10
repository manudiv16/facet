// Pure task helpers: validation, filtering, sorting and hierarchy flattening.
//
// Everything here is side-effect free so it can be unit tested without a DOM
// or a network. The reactive stores in `$stores/tasks` are thin wrappers.
import type {
	Task,
	TaskCreate,
	TaskFilters,
	TaskLevel,
	TaskPriority,
	TaskStatus,
	TaskTreeRow,
} from "./types";

export const LEVELS: readonly TaskLevel[] = ["epic", "ticket", "task"];
export const PRIORITIES: readonly TaskPriority[] = [
	"low",
	"medium",
	"high",
	"critical",
];
export const STATUSES: readonly TaskStatus[] = [
	"todo",
	"in_progress",
	"blocked",
	"done",
	"cancelled",
	"archived",
];

export const LEVEL_LABELS: Record<TaskLevel, string> = {
	epic: "Epic",
	ticket: "Ticket",
	task: "Task",
};

export const PRIORITY_LABELS: Record<TaskPriority, string> = {
	low: "Low",
	medium: "Medium",
	high: "High",
	critical: "Critical",
};

export const STATUS_LABELS: Record<TaskStatus, string> = {
	todo: "Todo",
	in_progress: "In progress",
	blocked: "Blocked",
	done: "Done",
	cancelled: "Cancelled",
	archived: "Archived",
};

/** Lower rank sorts first. Epics lead their hierarchy. */
export const LEVEL_RANK: Record<TaskLevel, number> = {
	epic: 0,
	ticket: 1,
	task: 2,
};

/** Lower rank sorts first (critical is the most urgent). */
export const PRIORITY_RANK: Record<TaskPriority, number> = {
	critical: 0,
	high: 1,
	medium: 2,
	low: 3,
};

/** Statuses that mean a task can no longer block another task. */
const TERMINAL_STATUSES = new Set<TaskStatus>(["done", "cancelled", "archived"]);

export function isTerminalStatus(status: TaskStatus): boolean {
	return TERMINAL_STATUSES.has(status);
}

export function defaultTaskFilters(): TaskFilters {
	return {
		level: "all",
		status: "all",
		priority: "all",
		readyOnly: false,
		search: "",
	};
}

export interface TaskFormInput {
	title: string;
	description?: string;
	level: string;
	priority: string;
	parent_id?: string | null;
	tags?: string[];
}

export interface TaskFormErrors {
	title?: string;
	level?: string;
	priority?: string;
	parent_id?: string;
}

/**
 * Validate a create/edit payload without touching the network.
 *
 * Returns an error object. An empty object means the form is valid, so the
 * UI can short-circuit and never issue a request for a missing title.
 */
export function validateTaskForm(
	input: TaskFormInput,
	options: { existingIds?: ReadonlySet<string> } = {},
): TaskFormErrors {
	const errors: TaskFormErrors = {};

	if (!input.title || input.title.trim() === "") {
		errors.title = "Title is required";
	} else if (input.title.trim().length > 200) {
		errors.title = "Title must be 200 characters or fewer";
	}

	if (!LEVELS.includes(input.level as TaskLevel)) {
		errors.level = `Level must be one of: ${LEVELS.join(", ")}`;
	}

	if (!PRIORITIES.includes(input.priority as TaskPriority)) {
		errors.priority = `Priority must be one of: ${PRIORITIES.join(", ")}`;
	}

	if (
		input.parent_id &&
		options.existingIds &&
		!options.existingIds.has(input.parent_id)
	) {
		errors.parent_id = "Parent task no longer exists";
	}

	return errors;
}

export function hasFormErrors(errors: TaskFormErrors): boolean {
	return Object.keys(errors).length > 0;
}

/**
 * Turn raw form state into either validation errors or a clean payload.
 *
 * The `payload` is `null` whenever validation fails, which is the mechanism
 * that guarantees an invalid form (e.g. a missing title) never reaches the
 * network.
 */
export function buildTaskSubmission(
	input: TaskFormInput,
	options: { existingIds?: ReadonlySet<string> } = {},
): { errors: TaskFormErrors; payload: TaskCreate | null } {
	const errors = validateTaskForm(input, options);
	if (hasFormErrors(errors)) return { errors, payload: null };

	return {
		errors,
		payload: {
			title: input.title.trim(),
			description: input.description ?? "",
			level: input.level as TaskLevel,
			priority: input.priority as TaskPriority,
			parent_id: input.parent_id ?? null,
			// Trim and drop empty tags so no caller can smuggle blanks through.
			tags: (input.tags ?? [])
				.map((tag) => tag.trim())
				.filter((tag) => tag.length > 0),
		},
	};
}

/**
 * True when a task satisfies every active filter.
 * `readyIds` is the set returned by the ready queue; when omitted the
 * ready filter is ignored (used for optimistic views that are not ready-aware).
 */
export function matchesFilters(
	task: Task,
	filters: TaskFilters,
	readyIds?: ReadonlySet<string>,
): boolean {
	if (filters.level !== "all" && task.level !== filters.level) return false;
	if (filters.status !== "all" && task.status !== filters.status) return false;
	if (filters.priority !== "all" && task.priority !== filters.priority)
		return false;
	if (filters.readyOnly) {
		if (!readyIds || !readyIds.has(task.id)) return false;
	}

	const search = filters.search.trim().toLowerCase();
	if (search !== "") {
		const haystack = `${task.short_id} ${task.title} ${task.tags.join(" ")}`
			.toLowerCase();
		if (!haystack.includes(search)) return false;
	}

	return true;
}

export function filterTasks(
	tasks: readonly Task[],
	filters: TaskFilters,
	readyIds?: ReadonlySet<string>,
): Task[] {
	return tasks.filter((task) => matchesFilters(task, filters, readyIds));
}

/** Stable ordering: level, then priority, then short_id. */
export function compareTasks(a: Task, b: Task): number {
	const byLevel = LEVEL_RANK[a.level] - LEVEL_RANK[b.level];
	if (byLevel !== 0) return byLevel;

	const byPriority = PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
	if (byPriority !== 0) return byPriority;

	return a.short_id.localeCompare(b.short_id);
}

export function sortTasks(tasks: readonly Task[]): Task[] {
	return [...tasks].sort(compareTasks);
}

/**
 * Flatten the task hierarchy into ordered list rows with a depth.
 *
 * Children are grouped by `parent_id`. A task whose parent is absent from the
 * set (filtered out or deleted) is treated as a root so nothing disappears.
 * `collapsedIds` lets the UI fold a subtree; the collapsed node itself is
 * still emitted.
 */
export function buildTaskTreeRows(
	tasks: readonly Task[],
	options: { collapsedIds?: ReadonlySet<string> } = {},
): TaskTreeRow[] {
	const collapsed = options.collapsedIds ?? new Set<string>();
	const byId = new Map(tasks.map((task) => [task.id, task] as const));
	const childrenOf = new Map<string | null, Task[]>();

	for (const task of tasks) {
		const parentId =
			task.parent_id !== null && byId.has(task.parent_id)
				? task.parent_id
				: null;
		const bucket = childrenOf.get(parentId);
		if (bucket) {
			bucket.push(task);
		} else {
			childrenOf.set(parentId, [task]);
		}
	}
	for (const bucket of childrenOf.values()) {
		bucket.sort(compareTasks);
	}

	const rows: TaskTreeRow[] = [];
	const walk = (parentId: string | null, depth: number) => {
		const children = childrenOf.get(parentId);
		if (!children) return;
		for (const task of children) {
			const hasChildren = (childrenOf.get(task.id)?.length ?? 0) > 0;
			rows.push({ task, depth, hasChildren });
			if (hasChildren && !collapsed.has(task.id)) {
				walk(task.id, depth + 1);
			}
		}
	};
	walk(null, 0);

	return rows;
}

/** Format a Unix epoch (seconds) for display, tolerating missing timestamps. */
export function formatTimestamp(seconds: number | null | undefined): string {
	if (!seconds) return "—";
	const date = new Date(seconds * 1000);
	if (Number.isNaN(date.getTime())) return "—";
	return date.toLocaleString();
}
