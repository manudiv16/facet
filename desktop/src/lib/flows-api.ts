// Flows API — HTTP access to the Crystalline flow-instance endpoints (C7).
//
// Endpoint contract (Crystalline `http/routes/flows.gleam`):
//   POST   /api/v1/tasks/:task_id/flow           { template_id } → instantiate (201)
//   GET    /api/v1/tasks/:task_id/flow           instance + execution state (404 unbound)
//   DELETE /api/v1/tasks/:task_id/flow           unassign a finished flow (200; 404 unbound; 409 active)
//   POST   /api/v1/flows/:instance_id/advance
//   POST   /api/v1/flows/:instance_id/complete   { output }
//   POST   /api/v1/flows/:instance_id/input      { input }
//   POST   /api/v1/flows/:instance_id/reject     { reason }
//
// Template CRUD and the transitions sub-resource live in
// `flow-templates-api.ts`; both modules share `flow-model`'s normalisers.
// The prefix is centralised so it can be aligned with `src/facet/client.gleam`
// (which uses unprefixed paths) without touching every call site.

import { api } from "./api";
import {
	normalizeAdvance,
	normalizeState,
	type NormalizedAdvance,
} from "./flow-model";
import type {
	FlowExecutionState,
} from "./types";

export const API_PREFIX = "/api/v1";
const TASKS = `${API_PREFIX}/tasks`;
const FLOWS = `${API_PREFIX}/flows`;

function encode(value: string): string {
	return encodeURIComponent(value);
}

/** A 404 from the engine: `{ status: 404, message }` thrown by `api`. */
function isNotFound(error: unknown): boolean {
	return (
		typeof error === "object" &&
		error !== null &&
		"status" in error &&
		error.status === 404
	);
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
		if (isNotFound(error)) return null;
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

/**
 * Detach a task from its flow instance and delete that instance
 * (`DELETE /tasks/:id/flow`).
 *
 * The engine only allows this once the execution is terminal, so a `409`
 * (`Cannot unassign flow: execution is <status>`) is surfaced to the caller.
 */
export async function unassignTaskFlow(taskId: string): Promise<void> {
	await api.delete<unknown>(`${TASKS}/${encode(taskId)}/flow`);
}

/** Advance one engine step. Accepts the `{state, action}` or action-only shape. */
export async function advanceFlow(
	instanceId: string,
): Promise<NormalizedAdvance> {
	const raw = await api.post<unknown>(`${FLOWS}/${encode(instanceId)}/advance`, {});
	return normalizeAdvance(raw);
}

/**
 * Report the output of the running step and receive the next action.
 *
 * The engine identifies the step through the execution's `current_node_id`, so
 * only the instance id and output are sent (`POST /flows/:id/complete`).
 */
export async function completeStep(
	instanceId: string,
	output: string,
): Promise<NormalizedAdvance> {
	const raw = await api.post<unknown>(
		`${FLOWS}/${encode(instanceId)}/complete`,
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
