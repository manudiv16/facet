// Tasks API — HTTP access to the Crystalline Tasks endpoints.
//
// Endpoint contract (Crystalline C6, `http/routes/tasks.gleam`):
//   POST   /api/v1/tasks
//   GET    /api/v1/tasks             ?level&status&parent_id&limit&offset
//   GET    /api/v1/tasks/ready
//   GET    /api/v1/tasks/:id
//   PATCH  /api/v1/tasks/:id
//   DELETE /api/v1/tasks/:id         ?cascade=true
//   POST   /api/v1/tasks/:id/dependencies          { depends_on }
//   DELETE /api/v1/tasks/:id/dependencies/:depends_on
//   GET    /api/v1/tasks/:id/blockers
//
// The prefix is centralised so it can be aligned with `src/facet/client.gleam`
// (which keeps the same `/api/v1` convention) without touching every call site.
import { api } from "./api";
import type {
	Task,
	TaskCreate,
	TaskLevel,
	TaskPatch,
	TaskPriority,
	TaskStatus,
} from "./types";

export const API_PREFIX = "/api/v1";
const TASKS = `${API_PREFIX}/tasks`;

export interface ListTasksParams {
	level?: TaskLevel;
	status?: TaskStatus;
	parent_id?: string;
	limit?: number;
	offset?: number;
}

/** Coerce a wire payload into a fully-populated `Task`. */
export function normalizeTask(raw: Partial<Task> & { id: string }): Task {
	return {
		id: raw.id,
		short_id: raw.short_id ?? raw.id.slice(0, 8),
		title: raw.title ?? "",
		description: raw.description ?? "",
		level: (raw.level ?? "task") as TaskLevel,
		priority: (raw.priority ?? "medium") as TaskPriority,
		status: (raw.status ?? "todo") as TaskStatus,
		tags: Array.isArray(raw.tags) ? raw.tags : [],
		parent_id: raw.parent_id ?? null,
		flow_template_id: raw.flow_template_id ?? null,
		flow_instance_id: raw.flow_instance_id ?? null,
		current_node_id: raw.current_node_id ?? null,
		worktree: raw.worktree ?? null,
		archived: raw.archived ?? false,
		created_at: raw.created_at ?? 0,
		updated_at: raw.updated_at ?? 0,
	};
}

export async function listTasks(
	params: ListTasksParams = {},
): Promise<Task[]> {
	const search = new URLSearchParams();
	if (params.level) search.set("level", params.level);
	if (params.status) search.set("status", params.status);
	if (params.parent_id) search.set("parent_id", params.parent_id);
	search.set("limit", String(params.limit ?? 200));
	if (params.offset !== undefined) search.set("offset", String(params.offset));

	const query = search.toString();
	const raw = await api.get<Partial<Task>[]>(`${TASKS}?${query}`);
	return raw.map((task) => normalizeTask(task as Partial<Task> & { id: string }));
}

export async function listReadyTasks(): Promise<Task[]> {
	const raw = await api.get<Partial<Task>[]>(`${TASKS}/ready`);
	return raw.map((task) => normalizeTask(task as Partial<Task> & { id: string }));
}

export async function getTask(id: string): Promise<Task> {
	const raw = await api.get<Partial<Task>>(`${TASKS}/${encodeURIComponent(id)}`);
	return normalizeTask(raw as Partial<Task> & { id: string });
}

export async function createTask(input: TaskCreate): Promise<Task> {
	const body = {
		title: input.title,
		description: input.description ?? "",
		level: input.level,
		priority: input.priority,
		parent_id: input.parent_id ?? null,
		tags: input.tags ?? [],
	};
	const raw = await api.post<Partial<Task>>(TASKS, body);
	return normalizeTask(raw as Partial<Task> & { id: string });
}

export async function updateTask(id: string, patch: TaskPatch): Promise<Task> {
	const raw = await api.patch<Partial<Task>>(
		`${TASKS}/${encodeURIComponent(id)}`,
		patch,
	);
	return normalizeTask(raw as Partial<Task> & { id: string });
}

export async function archiveTask(
	id: string,
	cascade = false,
): Promise<void> {
	const suffix = cascade ? "?cascade=true" : "";
	await api.delete(`${TASKS}/${encodeURIComponent(id)}${suffix}`);
}

export async function addDependency(
	taskId: string,
	dependsOn: string,
): Promise<void> {
	await api.post(`${TASKS}/${encodeURIComponent(taskId)}/dependencies`, {
		depends_on: dependsOn,
	});
}

export async function removeDependency(
	taskId: string,
	dependsOn: string,
): Promise<void> {
	await api.delete(
		`${TASKS}/${encodeURIComponent(taskId)}/dependencies/${encodeURIComponent(dependsOn)}`,
	);
}

/** Incomplete blockers only: the server filters out terminal blockers. */
export async function getBlockers(taskId: string): Promise<Task[]> {
	const raw = await api.get<Partial<Task>[]>(
		`${TASKS}/${encodeURIComponent(taskId)}/blockers`,
	);
	return raw.map((task) => normalizeTask(task as Partial<Task> & { id: string }));
}
