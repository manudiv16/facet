// Svelte stores for tasks.
//
// The list store is a single app-wide instance; the detail store is a factory
// so it can be created per route and torn down. Every mutation is optimistic:
// we apply it locally, call Crystalline, and roll back to the captured
// previous value if the request fails. The server message is surfaced through
// `mutationError` (list) or `$detail.mutationError` so the UI can render it
// inline.
import { derived, get, writable, type Readable } from "svelte/store";
import type { ApiError } from "$lib/api";
import * as artifactsApi from "$lib/artifacts-api";
import * as sectionsApi from "$lib/sections-api";
import * as tasksApi from "$lib/tasks-api";
import type {
	Artifact,
	Section,
	SectionCreateInput,
	SectionUpdateInput,
	Task,
	TaskCreate,
	TaskFilters,
	TaskPatch,
} from "$lib/types";
import {
	buildTaskTreeRows,
	defaultTaskFilters,
	filterTasks,
	sortTasks,
} from "$lib/tasks-utils";

export function errorMessage(error: unknown): string {
	if (error && typeof error === "object" && "message" in error) {
		const message = (error as ApiError).message;
		if (typeof message === "string" && message.length > 0) return message;
	}
	if (error instanceof Error && error.message) return error.message;
	return "Something went wrong";
}

function nowSeconds(): number {
	return Math.floor(Date.now() / 1000);
}

// ─── List store ─────────────────────────────────────────────────────────────

export const tasks = writable<Task[]>([]);
export const readyIds = writable<Set<string>>(new Set());
export const filters = writable<TaskFilters>(defaultTaskFilters());
export const collapsedIds = writable<Set<string>>(new Set());
export const loading = writable(false);
export const error = writable<string | null>(null);
export const mutationError = writable<string | null>(null);

export const filteredTasks = derived(
	[tasks, filters, readyIds],
	([$tasks, $filters, $readyIds]) =>
		sortTasks(filterTasks($tasks, $filters, $readyIds)),
);

export const taskRows = derived(
	[filteredTasks, collapsedIds],
	([$filteredTasks, $collapsedIds]) =>
		buildTaskTreeRows($filteredTasks, { collapsedIds: $collapsedIds }),
);

export const taskCount = derived(tasks, ($tasks) => $tasks.length);

async function refreshReady(): Promise<void> {
	try {
		const ready = await tasksApi.listReadyTasks();
		readyIds.set(new Set(ready.map((task) => task.id)));
	} catch {
		// Ready-queue refresh is best-effort; the main list already loaded.
	}
}

export async function loadTasks(): Promise<void> {
	loading.set(true);
	error.set(null);
	try {
		const all = await tasksApi.listTasks({ limit: 200 });
		tasks.set(all);
	} catch (e) {
		error.set(errorMessage(e));
	} finally {
		loading.set(false);
	}
	await refreshReady();
}

export async function refreshTasks(): Promise<void> {
	const [all, ready] = await Promise.all([
		tasksApi.listTasks({ limit: 200 }),
		tasksApi.listReadyTasks().catch(() => [] as Task[]),
	]);
	tasks.set(all);
	readyIds.set(new Set(ready.map((task) => task.id)));
}

export function setFilter<K extends keyof TaskFilters>(
	key: K,
	value: TaskFilters[K],
): void {
	filters.update((current) => ({ ...current, [key]: value }));
}

export function resetFilters(): void {
	filters.set(defaultTaskFilters());
}

export function toggleCollapsed(taskId: string): void {
	collapsedIds.update((current) => {
		const next = new Set(current);
		if (next.has(taskId)) next.delete(taskId);
		else next.add(taskId);
		return next;
	});
}

export function taskById(id: string): Task | undefined {
	return get(tasks).find((task) => task.id === id);
}

// ─── List mutations (optimistic, rollback on error) ─────────────────────────

export async function createTaskOptimistic(input: TaskCreate): Promise<Task> {
	const optimistic: Task = {
		id: `temp-${crypto.randomUUID()}`,
		short_id: "pending",
		title: input.title,
		description: input.description ?? "",
		level: input.level,
		priority: input.priority,
		status: "todo",
		tags: input.tags ?? [],
		parent_id: input.parent_id ?? null,
		archived: false,
		created_at: nowSeconds(),
		updated_at: nowSeconds(),
	};

	tasks.update((list) => [optimistic, ...list]);
	mutationError.set(null);

	try {
		const created = await tasksApi.createTask(input);
		tasks.update((list) =>
			list.map((task) => (task.id === optimistic.id ? created : task)),
		);
		if (created.status !== "done") {
			readyIds.update((set) => new Set(set).add(created.id));
		}
		return created;
	} catch (e) {
		tasks.update((list) => list.filter((task) => task.id !== optimistic.id));
		mutationError.set(errorMessage(e));
		throw e;
	}
}

export async function updateTaskOptimistic(
	id: string,
	patch: TaskPatch,
): Promise<Task> {
	let previous: Task | undefined;

	tasks.update((list) =>
		list.map((task) => {
			if (task.id !== id) return task;
			previous = task;
			return { ...task, ...patch, updated_at: nowSeconds() };
		}),
	);
	mutationError.set(null);

	try {
		const updated = await tasksApi.updateTask(id, patch);
		tasks.update((list) =>
			list.map((task) => (task.id === id ? updated : task)),
		);
		if (updated.status === "done") {
			readyIds.update((set) => {
				const next = new Set(set);
				next.delete(id);
				return next;
			});
			await refreshReady();
		}
		return updated;
	} catch (e) {
		if (previous) {
			const restore = previous;
			tasks.update((list) =>
				list.map((task) => (task.id === id ? restore : task)),
			);
		}
		mutationError.set(errorMessage(e));
		throw e;
	}
}

export async function archiveTaskOptimistic(id: string): Promise<void> {
	let previous: Task[] = [];
	tasks.update((list) => {
		previous = list;
		return list.filter((task) => task.id !== id);
	});
	mutationError.set(null);

	try {
		await tasksApi.archiveTask(id);
		await refreshReady();
	} catch (e) {
		tasks.set(previous);
		mutationError.set(errorMessage(e));
		throw e;
	}
}

// ─── Detail store ───────────────────────────────────────────────────────────

export interface TaskDetailState {
	task: Task | null;
	blockers: Task[];
	blockersLoading: boolean;
	sections: Section[];
	sectionsLoading: boolean;
	/** Load or mutation failure for the sections panel; null when healthy. */
	sectionsError: string | null;
	artifacts: Artifact[];
	artifactsLoading: boolean;
	/** Load or mutation failure for the artifacts panel; null when healthy. */
	artifactsError: string | null;
	loading: boolean;
	notFound: boolean;
	error: string | null;
	mutationError: string | null;
}

export interface TaskDetailStore extends Readable<TaskDetailState> {
	load: () => Promise<void>;
	update: (patch: TaskPatch) => Promise<Task>;
	addBlocker: (dependsOn: string) => Promise<void>;
	removeBlocker: (dependsOn: string) => Promise<void>;
	refreshBlockers: () => Promise<void>;
	refreshSections: () => Promise<void>;
	createSection: (input: SectionCreateInput) => Promise<Section>;
	updateSection: (id: string, patch: SectionUpdateInput) => Promise<Section>;
	deleteSection: (id: string) => Promise<void>;
	refreshArtifacts: () => Promise<void>;
	saveArtifact: (logicalName: string, content: unknown) => Promise<Artifact>;
	deleteArtifact: (logicalName: string) => Promise<void>;
	/** Resolves when the initial task/blockers/sections/artifacts load settles. */
	ready: Promise<void>;
}

/**
 * A single self-contained store (not a bag of stores) so components can use
 * `$detail.task`, `$detail.blockers`, … directly.
 */
export function createTaskDetailStore(taskId: string): TaskDetailStore {
	const state = writable<TaskDetailState>({
		task: taskById(taskId) ?? null,
		blockers: [],
		blockersLoading: true,
		sections: [],
		sectionsLoading: true,
		sectionsError: null,
		artifacts: [],
		artifactsLoading: true,
		artifactsError: null,
		loading: true,
		notFound: false,
		error: null,
		mutationError: null,
	});

	function setState(partial: Partial<TaskDetailState>): void {
		state.update((current) => ({ ...current, ...partial }));
	}

	async function refreshBlockers(): Promise<void> {
		setState({ blockersLoading: true });
		try {
			setState({ blockers: await tasksApi.getBlockers(taskId) });
		} catch (e) {
			setState({ mutationError: errorMessage(e) });
		} finally {
			setState({ blockersLoading: false });
		}
	}

	/**
	 * Reload the task's sections. A failure (network, or a build without the
	 * route) sets `sectionsError` so the panel can render it inline instead of
	 * pretending there are none.
	 */
	async function refreshSections(): Promise<void> {
		setState({ sectionsLoading: true, sectionsError: null });
		try {
			setState({
				sections: sectionsApi.sortSections(
					await sectionsApi.listSections(taskId),
				),
			});
		} catch (e) {
			setState({ sectionsError: errorMessage(e) });
		} finally {
			setState({ sectionsLoading: false });
		}
	}

	async function createSection(input: SectionCreateInput): Promise<Section> {
		setState({ sectionsError: null });
		try {
			const created = await sectionsApi.createSection(taskId, input);
			// The engine appends at the next free order, so re-sorting keeps the
			// merged list in the same sequence the list endpoint would return.
			setState({
				sections: sectionsApi.sortSections([...get(state).sections, created]),
			});
			return created;
		} catch (e) {
			setState({ sectionsError: errorMessage(e) });
			throw e;
		}
	}

	async function updateSection(
		id: string,
		patch: SectionUpdateInput,
	): Promise<Section> {
		setState({ sectionsError: null });
		try {
			const updated = await sectionsApi.updateSection(id, patch);
			setState({
				sections: sectionsApi.sortSections(
					get(state).sections.map((section) =>
						section.id === id ? updated : section,
					),
				),
			});
			return updated;
		} catch (e) {
			setState({ sectionsError: errorMessage(e) });
			throw e;
		}
	}

	async function deleteSection(id: string): Promise<void> {
		const previous = get(state).sections;
		setState({
			sections: previous.filter((section) => section.id !== id),
			sectionsError: null,
		});
		try {
			await sectionsApi.deleteSection(id);
		} catch (e) {
			setState({ sections: previous, sectionsError: errorMessage(e) });
			throw e;
		}
	}

	/** Reload the task's artifacts; failures surface through `artifactsError`. */
	async function refreshArtifacts(): Promise<void> {
		setState({ artifactsLoading: true, artifactsError: null });
		try {
			setState({
				artifacts: await artifactsApi.listArtifacts(taskId),
			});
		} catch (e) {
			setState({ artifactsError: errorMessage(e) });
		} finally {
			setState({ artifactsLoading: false });
		}
	}

	/** Upsert one artifact by logical name and merge the stored row in place. */
	async function saveArtifact(
		logicalName: string,
		content: unknown,
	): Promise<Artifact> {
		setState({ artifactsError: null });
		try {
			const saved = await artifactsApi.putArtifact(
				taskId,
				logicalName,
				content,
			);
			setState({
				artifacts: artifactsApi.sortArtifacts([
					...get(state).artifacts.filter(
						(artifact) => artifact.logical_name !== saved.logical_name,
					),
					saved,
				]),
			});
			return saved;
		} catch (e) {
			setState({ artifactsError: errorMessage(e) });
			throw e;
		}
	}

	async function deleteArtifact(logicalName: string): Promise<void> {
		const previous = get(state).artifacts;
		setState({
			artifacts: previous.filter(
				(artifact) => artifact.logical_name !== logicalName,
			),
			artifactsError: null,
		});
		try {
			await artifactsApi.deleteArtifact(taskId, logicalName);
		} catch (e) {
			setState({ artifacts: previous, artifactsError: errorMessage(e) });
			throw e;
		}
	}

	async function load(): Promise<void> {
		setState({ loading: true, error: null, notFound: false });
		try {
			const fresh = await tasksApi.getTask(taskId);
			setState({ task: fresh });
			tasks.update((list) => {
				const index = list.findIndex((item) => item.id === fresh.id);
				if (index === -1) return [fresh, ...list];
				return list.map((item) => (item.id === fresh.id ? fresh : item));
			});
		} catch (e) {
			const message = errorMessage(e);
			setState({
				error: message,
				notFound: message.toLowerCase().includes("not found"),
			});
		} finally {
			setState({ loading: false });
		}
	}

	async function update(patch: TaskPatch): Promise<Task> {
		const previous = get(state).task;
		if (previous) {
			setState({ task: { ...previous, ...patch, updated_at: nowSeconds() } });
		}
		setState({ mutationError: null });

		try {
			const updated = await tasksApi.updateTask(taskId, patch);
			setState({ task: updated });
			tasks.update((list) =>
				list.map((item) => (item.id === updated.id ? updated : item)),
			);
			if (updated.status === "done") await refreshReady();
			return updated;
		} catch (e) {
			if (previous) setState({ task: previous });
			setState({ mutationError: errorMessage(e) });
			throw e;
		}
	}

	async function addBlocker(dependsOn: string): Promise<void> {
		const previous = get(state).blockers;
		const previousReady = get(readyIds);
		const dependent = get(tasks).find((item) => item.id === dependsOn);
		if (dependent) {
			setState({
				blockers: previous.some((item) => item.id === dependsOn)
					? previous
					: [...previous, dependent],
			});
		}
		// A task with an incomplete blocker is no longer ready.
		readyIds.update((set) => {
			const next = new Set(set);
			next.delete(taskId);
			return next;
		});
		setState({ mutationError: null });

		try {
			await tasksApi.addDependency(taskId, dependsOn);
			await refreshBlockers();
			await refreshReady();
		} catch (e) {
			readyIds.set(previousReady);
			setState({ blockers: previous, mutationError: errorMessage(e) });
			throw e;
		}
	}

	async function removeBlocker(dependsOn: string): Promise<void> {
		const previous = get(state).blockers;
		setState({
			blockers: previous.filter((item) => item.id !== dependsOn),
			mutationError: null,
		});

		try {
			await tasksApi.removeDependency(taskId, dependsOn);
			await refreshBlockers();
			await refreshReady();
		} catch (e) {
			setState({ blockers: previous, mutationError: errorMessage(e) });
			throw e;
		}
	}

	// Kick off loading immediately; callers can await `ready` for tests.
	const ready = (async () => {
		await Promise.all([
			load(),
			refreshBlockers(),
			refreshSections(),
			refreshArtifacts(),
		]);
	})();

	return {
		subscribe: state.subscribe,
		load,
		update,
		addBlocker,
		removeBlocker,
		refreshBlockers,
		refreshSections,
		createSection,
		updateSection,
		deleteSection,
		refreshArtifacts,
		saveArtifact,
		deleteArtifact,
		ready,
	};
}
