// Svelte stores for flow execution and the template catalogue.
//
// `createFlowStore` owns one task's active flow: it loads the execution state,
// exposes derived node statuses for the graph, and wraps the four control
// operations (advance / complete step / provide input / reject). The raw
// engine action is kept verbatim in `actionLog` for the debugging panel.

import { derived, get, writable, type Readable, type Writable } from "svelte/store";
import {
	isTerminalStatus,
} from "./flow-model";
import { deriveNodeStatuses } from "./flow-layout";
import {
	advanceFlow,
	completeStep,
	getTaskFlow,
	provideInput,
	rejectFlow,
	startFlow,
	unassignTaskFlow,
} from "./flows-api";
import { listTemplates } from "./flow-templates-api";
import type { NormalizedAdvance } from "./flow-model";
import { SEEDED_TEMPLATES } from "./seeded-templates";
import type { EngineAction, FlowExecutionState, FlowNodeStatus, FlowTemplate } from "./types";

export interface FlowActionLogEntry {
	at: number;
	action: EngineAction;
}

function describeError(error: unknown): string {
	if (error && typeof error === "object" && "message" in error) {
		const message = error.message;
		if (typeof message === "string" && message.length > 0) return message;
	}
	if (error instanceof Error) return error.message;
	return "Flow request failed";
}

/**
 * Resolve the step id to send to `/complete`. Prefers an in-flight step
 * record for the current node and falls back to the node id (older C7 builds
 * accept the node id).
 */
export function currentStepId(state: FlowExecutionState | null): string {
	if (!state?.current_node_id) return "";
	const nodeId = state.current_node_id;
	const inFlight = state.step_history.find(
		(step) =>
			step.node_id === nodeId &&
			step.id.length > 0 &&
			(step.status === "in_progress" ||
				step.status === "entered" ||
				step.status === "pending"),
	);
	return inFlight?.id ?? nodeId;
}

export interface FlowStore {
	state: Writable<FlowExecutionState | null>;
	action: Writable<EngineAction | null>;
	actionLog: Writable<FlowActionLogEntry[]>;
	loading: Writable<boolean>;
	busy: Writable<boolean>;
	error: Writable<string | null>;
	nodeStatuses: Readable<Record<string, FlowNodeStatus>>;
	currentNodeId: Readable<string | null>;
	instanceId: Readable<string | null>;
	awaitingInput: Readable<boolean>;
	terminal: Readable<boolean>;
	currentStep: Readable<string>;
	/** Set the task whose flow this store tracks. */
	setTask: (taskId: string) => void;
	load: (taskId: string) => Promise<FlowExecutionState | null>;
	start: (templateId: string) => Promise<void>;
	advance: () => Promise<void>;
	complete: (output: string) => Promise<void>;
	input: (text: string) => Promise<void>;
	reject: (reason?: string) => Promise<void>;
	/** Detach the task from its terminal flow instance (`DELETE /tasks/:id/flow`). */
	unassign: () => Promise<void>;
	refresh: () => Promise<FlowExecutionState | null>;
	reset: () => void;
}

export function createFlowStore(): FlowStore {
	const state = writable<FlowExecutionState | null>(null);
	const action = writable<EngineAction | null>(null);
	const actionLog = writable<FlowActionLogEntry[]>([]);
	const loading = writable(false);
	const busy = writable(false);
	const error = writable<string | null>(null);

	let taskId: string | null = null;

	const nodeStatuses = derived(state, ($state) => deriveNodeStatuses($state));
	const currentNodeId = derived(
		state,
		($state) => $state?.current_node_id ?? null,
	);
	const instanceId = derived(
		state,
		($state) => $state?.flow_instance.id ?? null,
	);
	const awaitingInput = derived(
		state,
		($state) => $state?.status === "awaiting_input",
	);
	const terminal = derived(state, ($state) =>
		$state ? isTerminalStatus($state.status) : false,
	);
	const currentStep = derived(state, ($state) => currentStepId($state));

	function recordAction(next: EngineAction | null): void {
		if (!next) return;
		action.set(next);
		actionLog.update((entries) => [...entries, { at: Date.now(), action: next }]);
	}

	function apply(payload: NormalizedAdvance): void {
		if (payload.state) state.set(payload.state);
		if (payload.action) recordAction(payload.action);
	}

	async function refresh(): Promise<FlowExecutionState | null> {
		if (!taskId) return null;
		const next = await getTaskFlow(taskId);
		state.set(next);
		return next;
	}

	function setTask(id: string): void {
		taskId = id;
	}

	async function load(id: string): Promise<FlowExecutionState | null> {
		taskId = id;
		loading.set(true);
		error.set(null);
		try {
			return await refresh();
		} catch (err) {
			error.set(describeError(err));
			return null;
		} finally {
			loading.set(false);
		}
	}

	async function run(operation: () => Promise<void>): Promise<void> {
		busy.set(true);
		error.set(null);
		try {
			await operation();
		} catch (err) {
			error.set(describeError(err));
		} finally {
			busy.set(false);
		}
	}

	async function start(templateId: string): Promise<void> {
		if (!taskId) {
			error.set("Select a task before starting a flow");
			return;
		}
		const id = taskId;
		await run(async () => {
			const next = await startFlow(id, templateId);
			state.set(next);
			action.set(null);
			actionLog.set([]);
		});
	}

	async function advance(): Promise<void> {
		const current = get(state);
		if (!current) return;
		const instanceId = current.flow_instance.id;
		await run(async () => {
			apply(await advanceFlow(instanceId));
			// Advance answers `{execution, action}`: the action is the payload,
			// the authoritative state (node, status, graph) comes from the task's
			// flow resource.
			await refresh();
		});
	}

	async function complete(output: string): Promise<void> {
		const current = get(state);
		if (!current) return;
		await run(async () => {
			apply(await completeStep(current.flow_instance.id, output));
			await refresh();
		});
	}

	async function input(text: string): Promise<void> {
		const current = get(state);
		if (!current) return;
		await run(async () => {
			apply(await provideInput(current.flow_instance.id, text));
			await refresh();
		});
	}

	async function reject(reason?: string): Promise<void> {
		const current = get(state);
		if (!current) return;
		await run(async () => {
			await rejectFlow(current.flow_instance.id, reason);
			action.set(null);
			await refresh();
		});
	}

	/**
	 * Detach the task from its (terminal) flow instance. The engine refuses
	 * with 409 while the execution is still pending/running/awaiting_input;
	 * that message lands in `error`.
	 */
	async function unassign(): Promise<void> {
		if (!taskId) {
			error.set("Select a task before unassigning a flow");
			return;
		}
		const id = taskId;
		await run(async () => {
			await unassignTaskFlow(id);
			state.set(null);
			action.set(null);
			actionLog.set([]);
		});
	}

	function reset(): void {
		state.set(null);
		action.set(null);
		actionLog.set([]);
		error.set(null);
		busy.set(false);
		loading.set(false);
		taskId = null;
	}

	return {
		state,
		action,
		actionLog,
		loading,
		busy,
		error,
		nodeStatuses,
		currentNodeId,
		instanceId,
		awaitingInput,
		terminal,
		currentStep,
		setTask,
		load,
		start,
		advance,
		complete,
		input,
		reject,
		unassign,
		refresh,
		reset,
	};
}

export interface TemplatesStore {
	templates: Writable<FlowTemplate[]>;
	loading: Writable<boolean>;
	error: Writable<string | null>;
	/** True when the API list was empty and the seeded catalogue is shown. */
	usingFallback: Writable<boolean>;
	load: (force?: boolean) => Promise<FlowTemplate[]>;
}

/** Template catalogue with a seeded fallback so slugs are always discoverable. */
export function createTemplatesStore(): TemplatesStore {
	const templates = writable<FlowTemplate[]>(SEEDED_TEMPLATES);
	const loading = writable(false);
	const error = writable<string | null>(null);
	const usingFallback = writable(true);
	let loaded = false;

	async function load(force = false): Promise<FlowTemplate[]> {
		if (loaded && !force) return get(templates);
		loading.set(true);
		error.set(null);
		try {
			const remote = await listTemplates();
			if (remote.length > 0) {
				templates.set(remote);
				usingFallback.set(false);
			} else {
				templates.set(SEEDED_TEMPLATES);
				usingFallback.set(true);
			}
		} catch (err) {
			error.set(describeError(err));
			templates.set(SEEDED_TEMPLATES);
			usingFallback.set(true);
		} finally {
			loaded = true;
			loading.set(false);
		}
		return get(templates);
	}

	return { templates, loading, error, usingFallback, load };
}
