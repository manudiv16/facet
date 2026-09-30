// Execution and session log types

export type ExecutionStatus =
	| "pending"
	| "entered"
	| "in_progress"
	| "running"
	| "awaiting_input"
	| "completed"
	| "failed"
	| "cancelled"
	| "rejected";

/**
 * One step execution as returned by `GET /api/v1/tasks/:id/executions`
 * (Crystalline C8). The list is ordered newest-first; each row carries the
 * node, model, token/cost metrics and timestamps rendered by the history table.
 */
export interface Execution {
	id: string;
	task_id: string;
	flow_instance_id?: string | null;
	execution_state_id?: string | null;
	node_id: string;
	status: ExecutionStatus;
	model?: string | null;
	input_tokens: number;
	output_tokens: number;
	cost: number;
	duration_ms: number;
	/** ISO timestamp of when the step started (normalised from `created_at`). */
	started_at: string | null;
	completed_at?: string | null;
	prompt?: string | null;
	output?: string | null;
	error?: string | null;
	/** Server-assigned ordering key, used as the `before_sequence` cursor. */
	sequence?: number;
}

/** Backwards-compatible alias: an execution row *is* a step execution. */
export type ExecutionStep = Execution;

export interface ExecutionAggregate {
	total_input_tokens: number;
	total_output_tokens: number;
	total_cost: number;
	total_duration_ms: number;
}

// Session log event types
export type SessionEventKind =
	| "text"
	| "tool_use"
	| "tool_result"
	| "usage"
	| "outcome"
	| "error";

export interface TextEvent {
	content: string;
}

export interface ToolUseEvent {
	tool_name: string;
	tool_input: Record<string, unknown>;
}

export interface ToolResultEvent {
	tool_name: string;
	output: string;
	truncated: boolean;
}

export interface UsageEvent {
	input_tokens: number;
	output_tokens: number;
}

export interface OutcomeEvent {
	success: boolean;
	result?: string;
}

export interface ErrorEvent {
	error_type: string;
	message: string;
	stack?: string;
}

export type SessionEventData =
	| TextEvent
	| ToolUseEvent
	| ToolResultEvent
	| UsageEvent
	| OutcomeEvent
	| ErrorEvent;

interface SessionEventBase {
	id: string;
	execution_id: string;
	sequence: number;
	timestamp: string;
}

// Discriminated union so that narrowing on `kind` also narrows `data`.
export type SessionEvent =
	| (SessionEventBase & { kind: "text"; data: TextEvent })
	| (SessionEventBase & { kind: "tool_use"; data: ToolUseEvent })
	| (SessionEventBase & { kind: "tool_result"; data: ToolResultEvent })
	| (SessionEventBase & { kind: "usage"; data: UsageEvent })
	| (SessionEventBase & { kind: "outcome"; data: OutcomeEvent })
	| (SessionEventBase & { kind: "error"; data: ErrorEvent });

export interface ExecutionListResponse {
	executions: Execution[];
	has_more: boolean;
	aggregate?: ExecutionAggregate;
}

export interface ExecutionStepsResponse {
	steps: ExecutionStep[];
	aggregate: ExecutionAggregate;
	has_more: boolean;
}

export interface SessionLogResponse {
	events: SessionEvent[];
	has_more: boolean;
}

// ─── Flow domain types ───────────────────────────────────────────────────────
//
// Canonical shape mirrors the shared models in facet's Gleam client (F1) and
// the Crystalline flows API (C7). The API layer normalises the wire format
// (nodes may arrive as a list or as a `{id: node}` map; engine actions may use
// a `kind` or `type` discriminator) into these types.

export type FlowNodeType =
	| "step"
	| "sequence"
	| "branch"
	| "loop"
	| "parallel"
	| "human_input";

/** Visual/execution state of a node in the graph. */
export type FlowNodeStatus =
	| "pending"
	| "running"
	| "awaiting_input"
	| "completed"
	| "failed";

export interface BranchRule {
	condition: string;
	target_id: string;
}

export interface LoopConfig {
	max_iterations?: number | null;
	exit_condition?: string | null;
	child_ids?: string[];
}

export interface AgentConfig {
	model: string;
	fallback_model?: string | null;
	system_prompt?: string | null;
	allowed_tools: string[];
	disallowed_tools: string[];
	permission_mode: string;
	max_budget_usd: number;
}

export interface FlowNode {
	id: string;
	name: string;
	node_type: FlowNodeType;
	/** Human-readable description of what the node does. */
	goal: string;
	prompt?: string | null;
	child_ids: string[];
	branch_rules: BranchRule[];
	loop_config?: LoopConfig | null;
	agent_config?: AgentConfig | null;
	output_schema?: string | null;
}

export interface FlowTransition {
	id: string;
	from_id: string;
	to_id: string;
	condition?: string | null;
	label?: string | null;
}

export interface FlowTemplate {
	id: string;
	/** Stable identifier used by the picker and the start request. */
	slug: string;
	name: string;
	description: string;
	initial_node_id: string;
	nodes: FlowNode[];
	transitions: FlowTransition[];
	on_done_template_id?: string | null;
	on_reject_template_id?: string | null;
	/** Present on list responses that omit the full graph. */
	node_count?: number;
	transition_count?: number;
}

// ─── Runtime execution state ─────────────────────────────────────────────────

export type FlowExecutionStatus =
	| "pending"
	| "running"
	| "awaiting_input"
	| "completed"
	| "rejected"
	| "failed"
	| "cancelled";

export type FlowStepStatus =
	| "pending"
	| "entered"
	| "in_progress"
	| "completed"
	| "failed"
	| "cancelled";

export interface FlowStepExecution {
	id: string;
	node_id: string;
	status: FlowStepStatus;
	prompt?: string | null;
	output?: string | null;
	transition_result?: string | null;
	model?: string | null;
	input_tokens: number;
	output_tokens: number;
	cost: number;
	duration_ms: number;
	created_at?: number;
	completed_at?: number | null;
}

export interface FlowInstance {
	id: string;
	template_id: string;
	task_id: string;
	nodes: FlowNode[];
	transitions: FlowTransition[];
	initial_node_id: string;
	on_done_template_id?: string | null;
	on_reject_template_id?: string | null;
}

export interface FlowExecutionState {
	id: string;
	flow_instance: FlowInstance;
	task_id: string;
	status: FlowExecutionStatus;
	current_node_id?: string | null;
	step_history: FlowStepExecution[];
	loop_counters: Record<string, number>;
	variables: Record<string, string>;
	parallel_active: string[];
	started_at?: number | null;
	completed_at?: number | null;
}

/** Action the engine asks the caller to perform after an advance. */
export type EngineActionKind =
	| "run_step"
	| "await_input"
	| "run_parallel"
	| "flow_complete"
	| "flow_reject"
	| "execution_error";

export interface EngineAction {
	kind: EngineActionKind | (string & {});
	node?: FlowNode;
	prompt?: string;
	children?: FlowNode[];
	message?: string;
	/** The unmodified JSON payload, rendered verbatim in the UI. */
	raw: unknown;
}

export interface AdvanceResult {
	state: FlowExecutionState;
	action: EngineAction;
}

// ─── Request bodies ──────────────────────────────────────────────────────────

export interface StartFlowRequest {
	template_id: string;
}

export interface CompleteStepRequest {
	output: string;
}

export interface ProvideInputRequest {
	input: string;
}

export interface RejectFlowRequest {
	reason?: string;
}


// ─── Task domain types ──────────────────────────────────────────────────────

/** Hierarchy level. Mirrors Crystalline `domain/task.gleam` (`Level`). */
export type TaskLevel = "epic" | "ticket" | "task";

export type TaskPriority = "low" | "medium" | "high" | "critical";

export type TaskStatus =
	| "todo"
	| "in_progress"
	| "blocked"
	| "done"
	| "cancelled"
	| "archived";

/**
 * A task as returned by `GET /api/v1/tasks`.
 *
 * `created_at` / `updated_at` are Unix epoch integers, matching the Gleam
 * decoder in `src/facet/client.gleam`. Flow position fields are optional
 * because the current C6 serializer omits them until flow execution lands.
 */
export interface Task {
	id: string;
	short_id: string;
	title: string;
	description: string;
	level: TaskLevel;
	priority: TaskPriority;
	status: TaskStatus;
	tags: string[];
	parent_id: string | null;
	flow_template_id?: string | null;
	flow_instance_id?: string | null;
	current_node_id?: string | null;
	worktree?: string | null;
	archived: boolean;
	created_at: number;
	updated_at: number;
}

/** Fields accepted by `POST /api/v1/tasks`. Title, level and priority are required. */
export interface TaskCreate {
	title: string;
	description?: string;
	level: TaskLevel;
	priority: TaskPriority;
	parent_id?: string | null;
	tags?: string[];
}

/** Partial update accepted by `PATCH /api/v1/tasks/:id`. */
export interface TaskPatch {
	title?: string;
	description?: string;
	priority?: TaskPriority;
	status?: TaskStatus;
	tags?: string[];
}

/** Client-side filter state for the list view. Not all are sent to the server. */
export interface TaskFilters {
	level: TaskLevel | "all";
	status: TaskStatus | "all";
	priority: TaskPriority | "all";
	readyOnly: boolean;
	search: string;
}

/** A task flattened for the list view with its hierarchy depth. */
export interface TaskTreeRow {
	task: Task;
	depth: number;
	hasChildren: boolean;
}

// ─── Task sections (structured description parts) ───────────────────────────

export type SectionType =
	| "goal"
	| "context"
	| "current_behavior"
	| "desired_behavior"
	| "checklist_item"
	| "testing_criterion"
	| "constraint"
	| "anti_pattern"
	| "failure_test";

export type ChecklistState = "done" | "undone";

export interface CodeRef {
	path: string;
	line_start?: number | null;
	line_end?: number | null;
	name?: string | null;
	description?: string | null;
}

export interface Section {
	id: string;
	task_id: string;
	section_type: SectionType;
	content: string;
	code_ref?: CodeRef | null;
	order: number;
	checklist_state?: ChecklistState | null;
}

/** Fields accepted by `POST /api/v1/tasks/:task_id/sections`. */
export interface SectionCreateInput {
	section_type: SectionType;
	content: string;
	code_ref?: CodeRef | null;
	/** Defaults to the next free position for the task when omitted. */
	order?: number;
	checklist_state?: ChecklistState | null;
}

/**
 * Partial update accepted by `PATCH /api/v1/sections/:id`.
 *
 * `code_ref` and `checklist_state` are tri-state on the wire: `null` clears
 * them, unlike an omitted key which leaves the stored value untouched.
 */
export interface SectionUpdateInput {
	section_type?: SectionType;
	content?: string;
	order?: number;
	code_ref?: CodeRef | null;
	checklist_state?: ChecklistState | null;
}

// ─── Task artifacts (named JSON blobs) ──────────────────────────────────────

/**
 * One named JSON artifact of a task, as returned by
 * `GET /api/v1/tasks/:task_id/artifacts` (Crystalline artifacts routes).
 *
 * `content` is whatever JSON the creator stored — an object, array, string,
 * number, boolean or null — and is rendered verbatim by the artifacts panel.
 */
export interface Artifact {
	id: string;
	task_id: string;
	logical_name: string;
	content: unknown;
	/** Unix epoch seconds, matching the task timestamp convention. */
	created_at: number;
	updated_at: number;
}
