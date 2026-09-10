// Flow model normalisation.
//
// The Crystalline flows API (C7) is still stabilising and its JSON has drifted
// between the shared Gleam client (F1) and the HTTP routes. This module turns
// every plausible wire shape into the canonical types in `types.ts`:
//
//   * nodes arrive either as a JSON array or as a `{ "id": node }` map
//   * node type fields are `node_type`, `type` or `nodeType`
//   * transitions use `from_id`/`to_id` or the legacy `from_node_id`/`to_node_id`
//   * engine actions use `kind` or `type` as the discriminator
//   * a "state" response may be nested under `state`, `flow_instance` or flat
//
// Keeping the coercion here means the components only ever see one shape.

import type {
	AgentConfig,
	BranchRule,
	EngineAction,
	FlowExecutionState,
	FlowExecutionStatus,
	FlowInstance,
	FlowNode,
	FlowNodeType,
	FlowStepExecution,
	FlowStepStatus,
	FlowTemplate,
	FlowTransition,
	LoopConfig,
} from "./types";

// ─── Coercion helpers ────────────────────────────────────────────────────────

function asRecord(value: unknown): Record<string, unknown> {
	if (value && typeof value === "object" && !Array.isArray(value)) {
		return value as Record<string, unknown>;
	}
	return {};
}

function asString(value: unknown, fallback = ""): string {
	return typeof value === "string" ? value : fallback;
}

function asNumber(value: unknown, fallback = 0): number {
	return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asOptionalString(value: unknown): string | null {
	return typeof value === "string" ? value : null;
}

function asStringArray(value: unknown): string[] {
	if (!Array.isArray(value)) return [];
	return value.filter((item): item is string => typeof item === "string");
}

function asNumberMap(value: unknown): Record<string, number> {
	const record = asRecord(value);
	const out: Record<string, number> = {};
	for (const [key, raw] of Object.entries(record)) {
		const numeric = asNumber(raw, Number.NaN);
		if (!Number.isNaN(numeric)) out[key] = numeric;
	}
	return out;
}

function asStringMap(value: unknown): Record<string, string> {
	const record = asRecord(value);
	const out: Record<string, string> = {};
	for (const [key, raw] of Object.entries(record)) {
		if (typeof raw === "string") out[key] = raw;
	}
	return out;
}

// ─── Nodes ───────────────────────────────────────────────────────────────────

const NODE_TYPES: FlowNodeType[] = [
	"step",
	"sequence",
	"branch",
	"loop",
	"parallel",
	"human_input",
];

/** Accept `human-input`, `humanInput`, `HumanInput`, `HUMAN_INPUT`, … */
export function normalizeNodeType(value: unknown): FlowNodeType {
	if (typeof value !== "string") return "step";
	const normalised = value
		.trim()
		.replace(/[\s-]+/g, "_")
		.replace(/([a-z0-9])([A-Z])/g, "$1_$2")
		.toLowerCase();
	const match = NODE_TYPES.find((type) => type === normalised);
	return match ?? "step";
}

export function normalizeNode(raw: unknown): FlowNode {
	const record = asRecord(raw);
	const nodeType = normalizeNodeType(
		record.node_type ?? record.nodeType ?? record.type,
	);
	const id = asString(record.id);
	return {
		id,
		name: asString(record.name, id),
		node_type: nodeType,
		goal: asString(record.goal ?? record.description),
		prompt: asOptionalString(record.prompt),
		child_ids: asStringArray(record.child_ids ?? record.childIds),
		branch_rules: Array.isArray(record.branch_rules)
			? record.branch_rules.map(normalizeBranchRule)
			: [],
		loop_config: normalizeLoopConfig(
			record.loop_config ?? record.loopConfig,
			record.max_iterations,
		),
		agent_config: record.agent_config
			? normalizeAgentConfig(record.agent_config)
			: null,
		output_schema: asOptionalString(record.output_schema),
	};
}

/** Nodes may be a list, a `{id: node}` map, or absent (list responses). */
export function normalizeNodes(raw: unknown): FlowNode[] {
	if (Array.isArray(raw)) return raw.map(normalizeNode);
	const record = asRecord(raw);
	const values = Object.values(record);
	if (values.length === 0) return [];
	return values.map(normalizeNode);
}

function normalizeBranchRule(raw: unknown): BranchRule {
	const record = asRecord(raw);
	return {
		condition: asString(record.condition),
		target_id: asString(record.target_id ?? record.target ?? record.targetId),
	};
}

function normalizeLoopConfig(
	raw: unknown,
	legacyMax?: unknown,
): LoopConfig | null {
	const record = asRecord(raw);
	const maxRaw = record.max_iterations ?? record.maxIterations ?? legacyMax;
	const exit = record.exit_condition ?? record.exitCondition;
	const childIds = record.child_ids ?? record.childIds;
	const hasAny =
		maxRaw != null || exit != null || Array.isArray(childIds) || raw != null;
	if (!hasAny) return null;
	return {
		max_iterations: typeof maxRaw === "number" ? maxRaw : null,
		exit_condition: asOptionalString(exit),
		child_ids: asStringArray(childIds),
	};
}

function normalizeAgentConfig(raw: unknown): AgentConfig {
	const record = asRecord(raw);
	return {
		model: asString(record.model),
		fallback_model: asOptionalString(record.fallback_model),
		system_prompt: asOptionalString(record.system_prompt),
		allowed_tools: asStringArray(record.allowed_tools),
		disallowed_tools: asStringArray(record.disallowed_tools),
		permission_mode: asString(record.permission_mode),
		max_budget_usd: asNumber(record.max_budget_usd),
	};
}

// ─── Transitions ─────────────────────────────────────────────────────────────

export function normalizeTransition(raw: unknown): FlowTransition {
	const record = asRecord(raw);
	return {
		id: asString(record.id),
		from_id: asString(
			record.from_id ?? record.from ?? record.from_node_id ?? record.fromId,
		),
		to_id: asString(
			record.to_id ?? record.to ?? record.to_node_id ?? record.toId,
		),
		condition: asOptionalString(record.condition),
		label: asOptionalString(record.label),
	};
}

function normalizeTransitions(raw: unknown): FlowTransition[] {
	if (!Array.isArray(raw)) return [];
	return raw.map(normalizeTransition);
}

// ─── Templates ───────────────────────────────────────────────────────────────

export function normalizeTemplate(raw: unknown): FlowTemplate {
	const record = asRecord(raw);
	const id = asString(record.id ?? record.slug);
	const nodes = normalizeNodes(record.nodes);
	const transitions = normalizeTransitions(record.transitions);
	const initial = asString(
		record.initial_node_id ?? record.entry_node_id ?? record.entryNodeId,
		nodes[0]?.id ?? "",
	);
	return {
		id,
		slug: asString(record.slug, id),
		name: asString(record.name, id),
		description: asString(record.description),
		initial_node_id: initial,
		nodes,
		transitions,
		on_done_template_id: asOptionalString(record.on_done_template_id),
		on_reject_template_id: asOptionalString(record.on_reject_template_id),
		node_count: asNumber(record.node_count, nodes.length),
		transition_count: asNumber(record.transition_count, transitions.length),
	};
}

/** Accepts `[...]`, `{templates: [...]}` or `{items: [...]}`. */
export function normalizeTemplateList(raw: unknown): FlowTemplate[] {
	if (Array.isArray(raw)) return raw.map(normalizeTemplate);
	const record = asRecord(raw);
	const list = record.templates ?? record.items ?? record.data;
	if (Array.isArray(list)) return list.map(normalizeTemplate);
	return [];
}

// ─── Instances & execution state ─────────────────────────────────────────────

export function normalizeInstance(raw: unknown): FlowInstance {
	const record = asRecord(raw);
	const nodes = normalizeNodes(record.nodes);
	const transitions = normalizeTransitions(record.transitions);
	return {
		id: asString(record.id),
		template_id: asString(record.template_id ?? record.templateId),
		task_id: asString(record.task_id ?? record.taskId),
		nodes,
		transitions,
		initial_node_id: asString(
			record.initial_node_id ?? record.initial_node_id,
			nodes[0]?.id ?? "",
		),
		on_done_template_id: asOptionalString(record.on_done_template_id),
		on_reject_template_id: asOptionalString(record.on_reject_template_id),
	};
}

const EXECUTION_STATUSES: FlowExecutionStatus[] = [
	"pending",
	"running",
	"awaiting_input",
	"completed",
	"rejected",
	"failed",
	"cancelled",
];

export function normalizeExecutionStatus(
	value: unknown,
): FlowExecutionStatus | null {
	if (typeof value !== "string") return null;
	const normalised = value.trim().toLowerCase();
	return EXECUTION_STATUSES.find((status) => status === normalised) ?? null;
}

const STEP_STATUSES: FlowStepStatus[] = [
	"pending",
	"entered",
	"in_progress",
	"completed",
	"failed",
	"cancelled",
];

function normalizeStepStatus(value: unknown): FlowStepStatus {
	if (typeof value !== "string") return "pending";
	const normalised = value.trim().toLowerCase();
	return STEP_STATUSES.find((status) => status === normalised) ?? "pending";
}

export function normalizeStep(raw: unknown): FlowStepExecution {
	const record = asRecord(raw);
	return {
		id: asString(record.id ?? record.step_id ?? record.stepId),
		node_id: asString(record.node_id ?? record.nodeId),
		status: normalizeStepStatus(record.status),
		prompt: asOptionalString(record.prompt),
		output: asOptionalString(record.output),
		transition_result: asOptionalString(record.transition_result),
		model: asOptionalString(record.model),
		input_tokens: asNumber(record.input_tokens),
		output_tokens: asNumber(record.output_tokens),
		cost: asNumber(record.cost),
		duration_ms: asNumber(record.duration_ms),
		created_at: typeof record.created_at === "number" ? record.created_at : undefined,
		completed_at:
			typeof record.completed_at === "number" ? record.completed_at : null,
	};
}

function normalizeSteps(raw: unknown): FlowStepExecution[] {
	if (!Array.isArray(raw)) return [];
	return raw.map(normalizeStep);
}

/**
 * Normalise an execution-state response.
 *
 * Handles:
 *   { id, status, current_node_id, flow_instance: {...}, step_history: [...] }
 *   { state: {...}, instance: {...} }
 *   { flow_instance: {...} }                       (instance only)
 */
export function normalizeState(raw: unknown): FlowExecutionState {
	const outer = asRecord(raw);
	const stateRecord = asRecord(outer.state ?? raw);
	const instanceSource =
		stateRecord.flow_instance ??
		stateRecord.flowInstance ??
		stateRecord.instance ??
		outer.flow_instance ??
		outer.flowInstance ??
		outer.instance ??
		stateRecord;
	const instance = normalizeInstance(instanceSource);

	return {
		id: asString(stateRecord.id ?? outer.id),
		flow_instance: instance,
		task_id: asString(
			stateRecord.task_id ?? outer.task_id ?? instance.task_id,
		),
		status:
			normalizeExecutionStatus(stateRecord.status ?? outer.status) ?? "pending",
		current_node_id: asOptionalString(
			stateRecord.current_node_id ?? outer.current_node_id,
		),
		step_history: normalizeSteps(
			stateRecord.step_history ?? outer.step_history,
		),
		loop_counters: asNumberMap(
			stateRecord.loop_counters ?? outer.loop_counters,
		),
		variables: asStringMap(stateRecord.variables ?? outer.variables),
		parallel_active: asStringArray(
			stateRecord.parallel_active ?? outer.parallel_active,
		),
		started_at:
			typeof (stateRecord.started_at ?? outer.started_at) === "number"
				? ((stateRecord.started_at ?? outer.started_at) as number)
				: null,
		completed_at:
			typeof (stateRecord.completed_at ?? outer.completed_at) === "number"
				? ((stateRecord.completed_at ?? outer.completed_at) as number)
				: null,
	};
}

// ─── Engine actions ──────────────────────────────────────────────────────────

export function normalizeAction(raw: unknown): EngineAction {
	const record = asRecord(raw);
	const kind = asString(record.kind ?? record.type ?? record.action, "unknown");
	const action: EngineAction = { kind, raw };

	switch (kind) {
		case "run_step": {
			action.node = normalizeNode(record.node);
			action.prompt = asString(record.prompt, action.node.goal);
			break;
		}
		case "await_input": {
			action.node = normalizeNode(record.node);
			break;
		}
		case "run_parallel": {
			action.children = Array.isArray(record.children)
				? record.children.map(normalizeNode)
				: [];
			break;
		}
		case "execution_error":
		case "error": {
			action.message = asString(record.message ?? record.error);
			break;
		}
		default:
			break;
	}
	return action;
}

export interface NormalizedAdvance {
	state: FlowExecutionState | null;
	action: EngineAction | null;
}

/**
 * Normalise an `/advance`, `/complete` or `/input` response, accepting either
 * the F1 envelope (`{state, action}`) or a state-only payload.
 */
export function normalizeAdvance(raw: unknown): NormalizedAdvance {
	const record = asRecord(raw);
	const actionSource =
		record.action ?? (record.kind || record.type ? raw : null);
	const stateSource = record.state ?? record.execution_state ?? null;

	const action = actionSource ? normalizeAction(actionSource) : null;

	let state: FlowExecutionState | null = null;
	if (stateSource) {
		state = normalizeState(stateSource);
	} else if (record.flow_instance || record.current_node_id !== undefined) {
		state = normalizeState(record);
	}

	return { state, action };
}

// ─── Derived helpers ─────────────────────────────────────────────────────────

const TERMINAL: FlowExecutionStatus[] = [
	"completed",
	"rejected",
	"failed",
	"cancelled",
];

export function isTerminalStatus(status: FlowExecutionStatus): boolean {
	return TERMINAL.includes(status);
}

export function templateNodeCount(template: FlowTemplate): number {
	return template.node_count ?? template.nodes.length;
}

export function templateTransitionCount(template: FlowTemplate): number {
	return template.transition_count ?? template.transitions.length;
}
