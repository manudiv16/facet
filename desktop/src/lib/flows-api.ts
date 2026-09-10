// Flows API — HTTP access to the Crystalline flow endpoints (C7).
//
// Endpoint contract (Crystalline C7, `http/routes/flows.gleam`):
//   GET    /api/v1/flow-templates
//   GET    /api/v1/flow-templates/:id
//   POST   /api/v1/tasks/:task_id/flow           { template_id }
//   GET    /api/v1/tasks/:task_id/flow
//   POST   /api/v1/flows/:instance_id/advance
//   POST   /api/v1/flows/:instance_id/steps/:step_id/complete  { output }
//   POST   /api/v1/flows/:instance_id/input                   { input }
//   POST   /api/v1/flows/:instance_id/reject                  { reason }
//
// The prefix is centralised so it can be aligned with `src/facet/client.gleam`
// (which uses unprefixed paths) without touching every call site.

import { api } from "./api";
import {
	normalizeAdvance,
	normalizeState,
	normalizeTemplate,
	normalizeTemplateList,
	type NormalizedAdvance,
} from "./flow-model";
import type {
	FlowExecutionState,
	FlowTemplate,
} from "./types";

export const API_PREFIX = "/api/v1";
const TEMPLATES = `${API_PREFIX}/flow-templates`;
const TASKS = `${API_PREFIX}/tasks`;
const FLOWS = `${API_PREFIX}/flows`;

function encode(value: string): string {
	return encodeURIComponent(value);
}

// ─── Templates ───────────────────────────────────────────────────────────────

/**
 * List flow templates. Used by the template picker; the response may omit the
 * node graph, so `node_count`/`transition_count` are honoured when present.
 */
export async function listTemplates(): Promise<FlowTemplate[]> {
	const raw = await api.get<unknown>(TEMPLATES);
	return normalizeTemplateList(raw);
}

export async function getTemplate(idOrSlug: string): Promise<FlowTemplate> {
	const raw = await api.get<unknown>(`${TEMPLATES}/${encode(idOrSlug)}`);
	return normalizeTemplate(raw);
}

// ─── Instances & execution ───────────────────────────────────────────────────

/**
 * Fetch the current flow execution for a task. Returns `null` when the task
 * has no flow bound yet (Crystalline answers 404).
 */
export async function getTaskFlow(
	taskId: string,
): Promise<FlowExecutionState | null> {
	try {
		const raw = await api.get<unknown>(`${TASKS}/${encode(taskId)}/flow`);
		return normalizeState(raw);
	} catch (error) {
		const status = (error as { status?: number } | null)?.status;
		if (status === 404) return null;
		throw error;
	}
}

/** Instantiate a template for a task and return the initial execution state. */
export async function startFlow(
	taskId: string,
	templateId: string,
): Promise<FlowExecutionState> {
	const raw = await api.post<unknown>(`${TASKS}/${encode(taskId)}/flow`, {
		template_id: templateId,
	});
	return normalizeState(raw);
}

/** Advance one engine step. Accepts the `{state, action}` or action-only shape. */
export async function advanceFlow(
	instanceId: string,
): Promise<NormalizedAdvance> {
	const raw = await api.post<unknown>(`${FLOWS}/${encode(instanceId)}/advance`, {});
	return normalizeAdvance(raw);
}

/** Complete the given step with an output string. */
export async function completeStep(
	instanceId: string,
	stepId: string,
	output: string,
): Promise<NormalizedAdvance> {
	const raw = await api.post<unknown>(
		`${FLOWS}/${encode(instanceId)}/steps/${encode(stepId)}/complete`,
		{ output },
	);
	return normalizeAdvance(raw);
}

/** Resume a flow waiting on `HumanInput`. */
export async function provideInput(
	instanceId: string,
	input: string,
): Promise<NormalizedAdvance> {
	const raw = await api.post<unknown>(`${FLOWS}/${encode(instanceId)}/input`, {
		input,
	});
	return normalizeAdvance(raw);
}

/** Reject a flow, optionally applying the template's reject chain. */
export async function rejectFlow(
	instanceId: string,
	reason?: string,
): Promise<FlowExecutionState> {
	const raw = await api.post<unknown>(`${FLOWS}/${encode(instanceId)}/reject`, {
		reason: reason ?? "",
	});
	return normalizeState(raw);
}
