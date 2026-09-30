// Flow template authoring API — Crystalline's template registry and its
// transition sub-resource (facet#10; engine issue #18).
//
// Endpoint contract:
//   GET    /api/v1/flow-templates
//   GET    /api/v1/flow-templates/:id
//   POST   /api/v1/flow-templates                          201 | 400 validator
//   PATCH  /api/v1/flow-templates/:id                      200 | 400 validator/unknown
//   DELETE /api/v1/flow-templates/:id                      200 | 404 unknown | 409 in use by N instance(s)
//   GET    /api/v1/flow-templates/:id/transitions
//   POST   /api/v1/flow-templates/:id/transitions          201 | 409 duplicate id | 400 validator
//   DELETE /api/v1/flow-templates/:id/transitions/:tid     200 | 404 unknown | 400 validator
//
// Task ↔ flow assignment (`POST`/`DELETE /api/v1/tasks/:task_id/flow`) lives in
// `flows-api.ts`, next to the rest of the instance lifecycle.
//
// Every rejection is rethrown as a `FlowTemplateError` carrying the HTTP status
// and the engine's message, so the authoring UI can render validator output
// inline instead of swallowing it.

import { api } from "./api";
import {
	normalizeTemplate,
	normalizeTemplateList,
	normalizeTransition,
} from "./flow-model";
import type { FlowNode, FlowTemplate, FlowTransition } from "./types";

export const API_PREFIX = "/api/v1";
const TEMPLATES = `${API_PREFIX}/flow-templates`;

function encode(value: string): string {
	return encodeURIComponent(value);
}

// ─── Errors ──────────────────────────────────────────────────────────────────

/**
 * A rejected template request. `status` is the engine's HTTP status
 * (400 validator, 404 unknown template/transition, 409 duplicate transition or
 * template still referenced by instances); `message` is the engine's own text,
 * which the UI shows next to the form.
 */
export class FlowTemplateError extends Error {
	readonly status: number;

	constructor(status: number, message: string) {
		super(message);
		this.name = "FlowTemplateError";
		this.status = status;
	}
}

/**
 * Why a template request failed, so the UI can decide what to keep on screen:
 * `validation` renders next to the form, `conflict` keeps the selection (a
 * template in use by instances must stay browsable), `not_found` clears it and
 * `network` means the engine never answered.
 */
export type TemplateErrorKind =
	| "validation"
	| "not_found"
	| "conflict"
	| "network";

export function classifyTemplateError(error: FlowTemplateError): TemplateErrorKind {
	switch (error.status) {
		case 400:
			return "validation";
		case 404:
			return "not_found";
		case 409:
			return "conflict";
		default:
			return "network";
	}
}

/**
 * Coerce the `{message, status}` object thrown by `api` (or a plain `Error`)
 * into a `FlowTemplateError`. Status 0 means the request never reached the
 * engine.
 */
export function toFlowTemplateError(error: unknown): FlowTemplateError {
	if (error instanceof FlowTemplateError) return error;
	if (error instanceof Error) return new FlowTemplateError(0, error.message);
	if (error && typeof error === "object") {
		const status = "status" in error ? error.status : undefined;
		const message = "message" in error ? error.message : undefined;
		const text =
			typeof message === "string" && message.length > 0
				? message
				: typeof status === "number"
					? `Request failed with status ${status}`
					: "Flow template request failed";
		if (typeof status === "number") return new FlowTemplateError(status, text);
		return new FlowTemplateError(0, text);
	}
	return new FlowTemplateError(0, "Flow template request failed");
}

async function guard<T>(operation: () => Promise<T>): Promise<T> {
	try {
		return await operation();
	} catch (error) {
		throw toFlowTemplateError(error);
	}
}

// ─── Request bodies ──────────────────────────────────────────────────────────

/** Fields accepted by `POST /flow-templates` and `PATCH /flow-templates/:id`. */
export interface FlowTemplateInput {
	name: string;
	description?: string;
	initial_node_id: string;
	nodes: FlowNode[];
	transitions: FlowTransition[];
	on_done_template_id?: string | null;
	on_reject_template_id?: string | null;
}

/** Body accepted when adding one transition to an existing template. */
export interface TransitionInput {
	id: string;
	from_id: string;
	to_id: string;
	condition?: string | null;
	label?: string | null;
}

/**
 * Render a node exactly as `codec.node_decoder/0` expects it: every field the
 * decoder requires is present, optional fields are `null` rather than absent.
 */
function serializeNode(node: FlowNode): Record<string, unknown> {
	return {
		id: node.id,
		name: node.name,
		node_type: node.node_type,
		goal: node.goal,
		prompt: node.prompt ?? null,
		child_ids: node.child_ids,
		branch_rules: node.branch_rules.map((rule) => ({
			condition: rule.condition,
			target_id: rule.target_id,
		})),
		loop_config: node.loop_config ?? null,
		agent_config: node.agent_config ?? null,
		output_schema: node.output_schema ?? null,
	};
}

function serializeTransition(
	transition: TransitionInput | FlowTransition,
): Record<string, unknown> {
	return {
		id: transition.id,
		from_id: transition.from_id,
		to_id: transition.to_id,
		condition: transition.condition ?? null,
		label: transition.label ?? null,
	};
}

/** Build the create/update body from a template input. */
export function templateBody(
	input: FlowTemplateInput,
): Record<string, unknown> {
	return {
		name: input.name,
		description: input.description ?? "",
		initial_node_id: input.initial_node_id,
		nodes: input.nodes.map(serializeNode),
		transitions: input.transitions.map(serializeTransition),
		on_done_template_id: input.on_done_template_id ?? null,
		on_reject_template_id: input.on_reject_template_id ?? null,
	};
}

// ─── Templates ───────────────────────────────────────────────────────────────

/**
 * `GET /api/v1/flow-templates` — every template with its node graph.
 *
 * The registry list is served by the prebuilt-registry handler, which answers
 * with `node_count`/`transition_count` but no graph. Each row is therefore
 * hydrated from its detail endpoint so callers always see nodes and
 * transitions; a row whose detail call fails is kept with its counts.
 */
export async function listTemplates(): Promise<FlowTemplate[]> {
	return guard(async () => {
		const listed = normalizeTemplateList(await api.get<unknown>(TEMPLATES));
		return Promise.all(
			listed.map(async (template) => {
				try {
					return normalizeTemplate(
						await api.get<unknown>(`${TEMPLATES}/${encode(template.id)}`),
					);
				} catch {
					return template;
				}
			}),
		);
	});
}

/** `GET /api/v1/flow-templates/:id` — one template (404 when unknown). */
export async function getTemplate(id: string): Promise<FlowTemplate> {
	return guard(async () =>
		normalizeTemplate(await api.get<unknown>(`${TEMPLATES}/${encode(id)}`)),
	);
}

/**
 * `POST /api/v1/flow-templates` — create a template.
 *
 * Rejects with status 400 when the validator refuses the graph; the message
 * names the first failure (cycle, self-transition, dangling ref, missing
 * initial node, step without prompt, composite node without children).
 */
export async function createTemplate(
	input: FlowTemplateInput,
): Promise<FlowTemplate> {
	return guard(async () =>
		normalizeTemplate(
			await api.post<unknown>(TEMPLATES, templateBody(input)),
		),
	);
}

/** `PATCH /api/v1/flow-templates/:id` — replace name/graph of a template. */
export async function updateTemplate(
	id: string,
	input: FlowTemplateInput,
): Promise<FlowTemplate> {
	return guard(async () =>
		normalizeTemplate(
			await api.patch<unknown>(
				`${TEMPLATES}/${encode(id)}`,
				templateBody(input),
			),
		),
	);
}

/**
 * `DELETE /api/v1/flow-templates/:id`.
 *
 * Rejects with 404 for an unknown id and 409 (`in use by N instance(s)`) while
 * any flow instance still references the template.
 */
export async function deleteTemplate(id: string): Promise<void> {
	return guard(async () => {
		await api.delete<unknown>(`${TEMPLATES}/${encode(id)}`);
	});
}

// ─── Transitions sub-resource ────────────────────────────────────────────────

/** `GET /api/v1/flow-templates/:id/transitions` — the stored transition list. */
export async function listTransitions(
	templateId: string,
): Promise<FlowTransition[]> {
	return guard(async () => {
		const raw = await api.get<unknown>(
			`${TEMPLATES}/${encode(templateId)}/transitions`,
		);
		if (!Array.isArray(raw)) return [];
		return raw.map(normalizeTransition);
	});
}

/**
 * `POST /api/v1/flow-templates/:id/transitions` — append one transition.
 *
 * Rejects with 409 when the id already exists and 400 when the resulting graph
 * fails validation (nothing is persisted).
 */
export async function addTransition(
	templateId: string,
	transition: TransitionInput,
): Promise<FlowTransition> {
	return guard(async () =>
		normalizeTransition(
			await api.post<unknown>(
				`${TEMPLATES}/${encode(templateId)}/transitions`,
				serializeTransition(transition),
			),
		),
	);
}

/**
 * `DELETE /api/v1/flow-templates/:id/transitions/:transition_id`.
 *
 * Rejects with 404 for an unknown transition and 400 when removing it leaves
 * the graph invalid (nothing is persisted).
 */
export async function removeTransition(
	templateId: string,
	transitionId: string,
): Promise<void> {
	return guard(async () => {
		await api.delete<unknown>(
			`${TEMPLATES}/${encode(templateId)}/transitions/${encode(transitionId)}`,
		);
	});
}
