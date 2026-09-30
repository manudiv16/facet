// Sections API — HTTP access to the Crystalline task-section endpoints.
//
// Endpoint contract (Crystalline `http/routes/sections.gleam`):
//   GET    /api/v1/tasks/:task_id/sections   ordered by `order`, then creation
//   POST   /api/v1/tasks/:task_id/sections   { section_type, content, code_ref?, order?, checklist_state? } → 201
//   GET    /api/v1/sections/:id
//   PATCH  /api/v1/sections/:id              partial; `null` clears code_ref/checklist_state → 200
//   DELETE /api/v1/sections/:id              → 200 { message }
//
// The wire shape already matches `Section` in `$lib/types`; the normalisation
// below only covers defensive corners (an absent `code_ref` object, a missing
// or non-numeric `order`, an unknown `checklist_state`) so the components can
// rely on the declared types.
import { api } from "./api";
import type {
	ChecklistState,
	CodeRef,
	Section,
	SectionCreateInput,
	SectionType,
	SectionUpdateInput,
} from "./types";

export const API_PREFIX = "/api/v1";
const TASKS = `${API_PREFIX}/tasks`;
const SECTIONS = `${API_PREFIX}/sections`;

function encode(value: string): string {
	return encodeURIComponent(value);
}

/** Coerce a wire payload into a fully-populated `Section`. */
export function normalizeSection(
	raw: Partial<Section> & { id: string },
): Section {
	const codeRefInput = raw.code_ref;
	const codeRef: CodeRef | null =
		codeRefInput !== null &&
		codeRefInput !== undefined &&
		typeof codeRefInput.path === "string" &&
		codeRefInput.path.length > 0
			? {
					path: codeRefInput.path,
					line_start:
						typeof codeRefInput.line_start === "number"
							? codeRefInput.line_start
							: null,
					line_end:
						typeof codeRefInput.line_end === "number"
							? codeRefInput.line_end
							: null,
					name: codeRefInput.name ?? null,
					description: codeRefInput.description ?? null,
				}
			: null;
	const checklistState: ChecklistState | null =
		raw.checklist_state === "done" || raw.checklist_state === "undone"
			? raw.checklist_state
			: null;
	return {
		id: raw.id,
		task_id: raw.task_id ?? "",
		section_type: raw.section_type as SectionType,
		content: raw.content ?? "",
		code_ref: codeRef,
		order:
			typeof raw.order === "number" && Number.isFinite(raw.order)
				? raw.order
				: 0,
		checklist_state: checklistState,
	};
}

/**
 * Stable `order` sort mirroring the engine's `ORDER BY "order", created_at`.
 *
 * The server already returns sections in this sequence; sorting again keeps a
 * locally-merged list (create/update responses) in the same sequence.
 */
export function sortSections(sections: Section[]): Section[] {
	return sections
		.map((section, index) => ({ section, index }))
		.sort((a, b) => a.section.order - b.section.order || a.index - b.index)
		.map((entry) => entry.section);
}

/** `GET /api/v1/tasks/:task_id/sections` — the task's sections, in order. */
export async function listSections(taskId: string): Promise<Section[]> {
	const payload = await api.get<unknown>(`${TASKS}/${encode(taskId)}/sections`);
	const items = Array.isArray(payload) ? payload : [];
	return sortSections(
		items.map((item) =>
			normalizeSection(item as Partial<Section> & { id: string }),
		),
	);
}

/** `GET /api/v1/sections/:id`. */
export async function getSection(id: string): Promise<Section> {
	const payload = await api.get<Partial<Section>>(`${SECTIONS}/${encode(id)}`);
	return normalizeSection(payload as Partial<Section> & { id: string });
}

/**
 * `POST /api/v1/tasks/:task_id/sections`.
 *
 * Only the keys the caller set are sent: the engine assigns the next free
 * `order` when it is omitted, and treats an absent `code_ref`/`checklist_state`
 * as "no value".
 */
export async function createSection(
	taskId: string,
	input: SectionCreateInput,
): Promise<Section> {
	const body: Record<string, unknown> = {
		section_type: input.section_type,
		content: input.content,
	};
	if (input.code_ref !== undefined) body.code_ref = input.code_ref;
	if (input.order !== undefined) body.order = input.order;
	if (input.checklist_state !== undefined) {
		body.checklist_state = input.checklist_state;
	}
	const payload = await api.post<Partial<Section>>(
		`${TASKS}/${encode(taskId)}/sections`,
		body,
	);
	return normalizeSection(payload as Partial<Section> & { id: string });
}

/** `PATCH /api/v1/sections/:id` — partial update of one section. */
export async function updateSection(
	id: string,
	patch: SectionUpdateInput,
): Promise<Section> {
	const payload = await api.patch<Partial<Section>>(
		`${SECTIONS}/${encode(id)}`,
		patch,
	);
	return normalizeSection(payload as Partial<Section> & { id: string });
}

/** `DELETE /api/v1/sections/:id`. */
export async function deleteSection(id: string): Promise<void> {
	await api.delete(`${SECTIONS}/${encode(id)}`);
}
