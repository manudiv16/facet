// Artifacts API — HTTP access to the Crystalline task artifact endpoints.
//
// Endpoint contract (Crystalline `http/routes/artifacts.gleam`):
//   GET    /api/v1/tasks/:task_id/artifacts                    ordered by logical_name
//   GET    /api/v1/tasks/:task_id/artifacts/:logical_name      → 200, or 404 when absent
//   PUT    /api/v1/tasks/:task_id/artifacts/:logical_name      { content } — upsert → 200
//   DELETE /api/v1/tasks/:task_id/artifacts/:logical_name      → 200 { message }
//
// `content` is arbitrary JSON, so it is passed through untouched; logical names
// are percent-encoded (the engine percent-decodes the path segment before use).
import { api } from "./api";
import type { Artifact } from "./types";

export const API_PREFIX = "/api/v1";
const TASKS = `${API_PREFIX}/tasks`;

function encode(value: string): string {
	return encodeURIComponent(value);
}

/** Coerce a wire payload into a fully-populated `Artifact`. */
export function normalizeArtifact(
	raw: Partial<Artifact> & { id: string },
): Artifact {
	return {
		id: raw.id,
		task_id: raw.task_id ?? "",
		logical_name: raw.logical_name ?? "",
		content: raw.content ?? null,
		created_at:
			typeof raw.created_at === "number" && Number.isFinite(raw.created_at)
				? raw.created_at
				: 0,
		updated_at:
			typeof raw.updated_at === "number" && Number.isFinite(raw.updated_at)
				? raw.updated_at
				: 0,
	};
}

/**
 * Stable `logical_name` sort mirroring the engine's `ORDER BY logical_name`.
 *
 * The list endpoint already returns this sequence; sorting again keeps the
 * locally-merged list (after a PUT) in the same sequence.
 */
export function sortArtifacts(artifacts: Artifact[]): Artifact[] {
	return [...artifacts].sort((a, b) =>
		a.logical_name < b.logical_name
			? -1
			: a.logical_name > b.logical_name
				? 1
				: 0,
	);
}

/** `GET /api/v1/tasks/:task_id/artifacts` — every artifact of a task. */
export async function listArtifacts(taskId: string): Promise<Artifact[]> {
	const payload = await api.get<unknown>(`${TASKS}/${encode(taskId)}/artifacts`);
	const items = Array.isArray(payload) ? payload : [];
	return sortArtifacts(
		items.map((item) =>
			normalizeArtifact(item as Partial<Artifact> & { id: string }),
		),
	);
}

/** `GET /api/v1/tasks/:task_id/artifacts/:logical_name`. */
export async function getArtifact(
	taskId: string,
	logicalName: string,
): Promise<Artifact> {
	const payload = await api.get<Partial<Artifact>>(
		`${TASKS}/${encode(taskId)}/artifacts/${encode(logicalName)}`,
	);
	return normalizeArtifact(payload as Partial<Artifact> & { id: string });
}

/**
 * `PUT /api/v1/tasks/:task_id/artifacts/:logical_name` — upsert the artifact's
 * content under `logicalName` and return the stored row.
 */
export async function putArtifact(
	taskId: string,
	logicalName: string,
	content: unknown,
): Promise<Artifact> {
	const payload = await api.put<Partial<Artifact>>(
		`${TASKS}/${encode(taskId)}/artifacts/${encode(logicalName)}`,
		{ content },
	);
	return normalizeArtifact(payload as Partial<Artifact> & { id: string });
}

/** `DELETE /api/v1/tasks/:task_id/artifacts/:logical_name`. */
export async function deleteArtifact(
	taskId: string,
	logicalName: string,
): Promise<void> {
	await api.delete(
		`${TASKS}/${encode(taskId)}/artifacts/${encode(logicalName)}`,
	);
}
