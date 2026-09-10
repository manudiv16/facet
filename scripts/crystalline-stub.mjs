#!/usr/bin/env node
// Development stub for the Crystalline sidecar.
//
// Crystalline's native binary is built by its own repository. Until it is
// available, scripts/dev-sidecar.sh installs this stub under the
// platform-suffixed name Tauri expects so the Facet shell can be exercised
// end to end (spawn, /health polling, status UI, graceful shutdown).
//
// Endpoints implemented (subset of facets' executions-api contract, C8):
//   GET  /health
//   GET  /api/v1/tasks                              seeded task list
//   GET  /api/v1/tasks/:id                          one task
//   GET  /api/v1/tasks/:id/executions      history (?limit&before_sequence)
//   GET  /api/v1/executions/active         running + awaiting_input (?limit)
//   GET  /api/v1/executions/:id            one step execution
//   GET  /api/v1/executions/:id/logs       session log page (?limit&before_sequence)
//   POST /api/v1/executions/:id/logs       append an event (payload: {event_type, payload})
//
// Pages are returned newest-first (sequence descending) with the `sequence`
// field the desktop uses as its `before_sequence` cursor; `has_more` reports
// whether older items remain, and execution list responses carry an
// `aggregate` footer (total tokens/cost across the whole task history).
import http from "node:http";

const port = Number(process.env.PORT || 8787);
const db = process.env.CRYSTALLINE_DB || null;
const version = "0.1.0-stub";

// The desktop shell fetches this API cross-origin: from the Vite dev server
// (`http://localhost:1420`) in the browser and from the Tauri webview origin in
// the packaged app. Crystalline answers with permissive CORS headers; the stub
// mirrors that so the UI is exercisable without a real engine.
const CORS_HEADERS = {
	"access-control-allow-origin": "*",
	"access-control-allow-methods": "GET, POST, PATCH, DELETE, OPTIONS",
	"access-control-allow-headers": "content-type, authorization",
	"access-control-max-age": "86400",
};

const NOW = Math.floor(Date.now() / 1000);

// ─── Seeded data ────────────────────────────────────────────────────────────

const tasks = [
	{
		id: "t-completed",
		short_id: "t-001",
		title: "Ship the thing",
		description: "Completed flow with tokens, cost and a full session log.",
		level: "ticket",
		priority: "high",
		status: "done",
		tags: ["facet", "demo"],
		parent_id: null,
		flow_template_id: "implement_review",
		flow_instance_id: "flow-1",
		current_node_id: null,
		worktree: null,
		archived: false,
		created_at: NOW - 86400,
		updated_at: NOW - 300,
	},
	{
		id: "t-live",
		short_id: "t-002",
		title: "Investigate flaky deploy",
		description: "A flow that is still in progress — exercises the 3s refresh.",
		level: "ticket",
		priority: "medium",
		status: "in_progress",
		tags: ["ops"],
		parent_id: null,
		flow_template_id: "design_implement",
		flow_instance_id: "flow-2",
		current_node_id: "design_review",
		worktree: null,
		archived: false,
		created_at: NOW - 3600,
		updated_at: NOW - 30,
	},
	{
		id: "t-big",
		short_id: "t-003",
		title: "Bulk import 2025",
		description: "120 completed steps so paging (page 2 prepend) can be seen.",
		level: "task",
		priority: "low",
		status: "done",
		tags: ["data"],
		parent_id: null,
		flow_template_id: "refactor_loop",
		flow_instance_id: "flow-3",
		current_node_id: null,
		worktree: null,
		archived: false,
		created_at: NOW - 604800,
		updated_at: NOW - 86400,
	},
];

/**
 * Task dependencies as `blockedTaskId -> Set<blockerId>`; blockers must reach a
 * terminal state before the dependent task leaves the ready queue.
 */
const blockedBy = new Map();

function step(
	id,
	taskId,
	{
		node,
		status,
		prompt,
		output,
		model,
		input,
		outputTokens,
		cost,
		duration,
		createdAt,
		completedAt,
		sequence,
	},
) {
	return {
		id,
		flow_instance_id: `flow-${taskId.replace("t-", "")}`,
		execution_state_id: `exec-${taskId.replace("t-", "")}`,
		node_id: node,
		task_id: taskId,
		status,
		prompt: prompt ?? null,
		output: output ?? null,
		transition_result: null,
		model: model ?? "claude-sonnet-4",
		input_tokens: input,
		output_tokens: outputTokens,
		cost,
		duration_ms: duration,
		session_id: null,
		created_at: createdAt,
		completed_at: completedAt ?? null,
		sequence,
	};
}

/** Ordered oldest → newest by sequence; list responses reverse it. */
const executionsByTask = {
	"t-completed": [
		step("ex-compl-build", "t-completed", {
			node: "build",
			status: "completed",
			output: "build completed",
			input: 1500,
			outputTokens: 300,
			cost: 0.0412,
			duration: 8120,
			createdAt: NOW - 600,
			completedAt: NOW - 592,
			sequence: 1,
		}),
		step("ex-compl-review", "t-completed", {
			node: "review",
			status: "completed",
			output: "review approved",
			input: 1200,
			outputTokens: 220,
			cost: 0.022,
			duration: 5330,
			createdAt: NOW - 560,
			completedAt: NOW - 554,
			sequence: 2,
		}),
	],
	"t-live": [
		step("ex-live-input", "t-live", {
			node: "approve",
			status: "awaiting_input",
			prompt: "Approve or reject the deploy",
			input: 400,
			outputTokens: 0,
			cost: 0.004,
			duration: 0,
			createdAt: NOW - 25,
			completedAt: null,
			sequence: 1,
		}),
		step("ex-live-deploy", "t-live", {
			node: "deploy",
			status: "in_progress",
			prompt: "Deploy the release candidate",
			input: 980,
			outputTokens: 140,
			cost: 0.011,
			duration: 12400,
			createdAt: NOW - 900,
			completedAt: null,
			sequence: 2,
		}),
	],
};

// 120 completed steps, sequential (page 1 = sequences 120..71).
{
	const rows = [];
	for (let seq = 1; seq <= 120; seq++) {
		rows.push(
			step(`ex-big-${seq}`, "t-big", {
				node: `import-row-${seq}`,
				status: "completed",
				output: `row ${seq} imported`,
				input: seq * 10,
				outputTokens: seq * 2,
				cost: seq * 0.0001,
				duration: seq * 500,
				createdAt: NOW - 604800 + seq * 20,
				completedAt: NOW - 604800 + seq * 20 + 5,
				sequence: seq,
			}),
		);
	}
	executionsByTask["t-big"] = rows;
}

function logEvent(id, execId, taskId, eventType, payload, sequence, createdAt) {
	return {
		id,
		step_execution_id: execId,
		task_id: taskId,
		event_type: eventType,
		payload: typeof payload === "string" ? payload : JSON.stringify(payload),
		sequence,
		created_at: createdAt,
	};
}

/** Session log events per execution, oldest → newest by sequence. */
const logsByExecution = {
	"ex-compl-build": [
		logEvent(
			"ev-build-1",
			"ex-compl-build",
			"t-completed",
			"text",
			{
				content: "Researching the current state of the deploy pipeline.",
			},
			1,
			NOW - 590,
		),
		logEvent(
			"ev-build-2",
			"ex-compl-build",
			"t-completed",
			"tool_use",
			{
				tool_name: "read",
				tool_input: { path: "src/lib/deploy.ts", offset: 12 },
			},
			2,
			NOW - 589,
		),
		logEvent(
			"ev-build-3",
			"ex-compl-build",
			"t-completed",
			"tool_result",
			{
				tool_name: "read",
				output: "const healthcheck = ...\n// healthcheck endpoint\n...",
				truncated: false,
			},
			3,
			NOW - 588,
		),
		logEvent(
			"ev-build-4",
			"ex-compl-build",
			"t-completed",
			"text",
			{
				content: "Patching the healthcheck and re-running the suite.",
			},
			4,
			NOW - 587,
		),
		logEvent(
			"ev-build-5",
			"ex-compl-build",
			"t-completed",
			"tool_use",
			{
				tool_name: "bash",
				tool_input: { command: "cargo test" },
			},
			5,
			NOW - 585,
		),
		logEvent(
			"ev-build-6",
			"ex-compl-build",
			"t-completed",
			"tool_result",
			{
				tool_name: "bash",
				output:
					"running 42 tests\n... 41 passed, 1 pending\n" +
					"Doc-tests facet\nrunning 3 tests\ntest src/lib/api.rs - api::request (line 12) ... ok\n" +
					"all tests passed",
				truncated: true,
			},
			6,
			NOW - 584,
		),
		logEvent(
			"ev-build-7",
			"ex-compl-build",
			"t-completed",
			"usage",
			{
				input_tokens: 1500,
				output_tokens: 300,
			},
			7,
			NOW - 583,
		),
		logEvent(
			"ev-build-8",
			"ex-compl-build",
			"t-completed",
			"text",
			{
				content: "Build green — leaving a summary for review.",
			},
			8,
			NOW - 582,
		),
		logEvent(
			"ev-build-9",
			"ex-compl-build",
			"t-completed",
			"outcome",
			{
				success: true,
				result: "build completed",
			},
			9,
			NOW - 581,
		),
	],
	"ex-compl-review": [
		logEvent(
			"ev-review-1",
			"ex-compl-review",
			"t-completed",
			"text",
			{
				content: "Reviewing the changeset.",
			},
			1,
			NOW - 555,
		),
		logEvent(
			"ev-review-2",
			"ex-compl-review",
			"t-completed",
			"usage",
			{
				input_tokens: 1200,
				output_tokens: 220,
			},
			2,
			NOW - 554,
		),
		logEvent(
			"ev-review-3",
			"ex-compl-review",
			"t-completed",
			"outcome",
			{
				success: true,
				result: "review approved",
			},
			3,
			NOW - 553,
		),
	],
	"ex-live-deploy": [
		logEvent(
			"ev-live-1",
			"ex-live-deploy",
			"t-live",
			"text",
			{
				content: "Deploying the release candidate to staging.",
			},
			1,
			NOW - 895,
		),
		logEvent(
			"ev-live-2",
			"ex-live-deploy",
			"t-live",
			"tool_use",
			{
				tool_name: "bash",
				tool_input: { command: "kubectl rollout status deploy/facet" },
			},
			2,
			NOW - 890,
		),
		logEvent(
			"ev-live-3",
			"ex-live-deploy",
			"t-live",
			"tool_result",
			{
				tool_name: "bash",
				output: "deployment rollout status: waiting for 2 replicas…",
				truncated: false,
			},
			3,
			NOW - 889,
		),
		logEvent(
			"ev-live-4",
			"ex-live-deploy",
			"t-live",
			"usage",
			{
				input_tokens: 980,
				output_tokens: 140,
			},
			4,
			NOW - 880,
		),
	],
	"ex-live-input": [
		logEvent(
			"ev-input-1",
			"ex-live-input",
			"t-live",
			"text",
			{
				content: "Awaiting human approval before promoting to production.",
			},
			1,
			NOW - 24,
		),
	],
};

// The newest t-big execution carries 120 text events so "Load older" on the
// session log has a second page to prepend (LOG_PAGE_SIZE = 100).
{
	const rows = [];
	for (let seq = 1; seq <= 120; seq++) {
		rows.push(
			logEvent(
				`ev-big-${seq}`,
				"ex-big-120",
				"t-big",
				"text",
				{
					content: `Bulk import progress: row ${seq} of 120 processed`,
				},
				seq,
				NOW - 86400 + seq * 5,
			),
		);
	}
	logsByExecution["ex-big-120"] = rows;
}

// ─── Flow templates ─────────────────────────────────────────────────────────

// Mirrors Crystalline's prebuilt registry (`flow/templates.gleam`, C11) and the
// desktop fallback catalogue in `desktop/src/lib/seeded-templates.ts`. Node ids,
// types and transitions match the engine definitions so the flow graph renders
// identically whichever source supplies it.

function stepNode(id, name, goal) {
	return {
		id,
		name,
		node_type: "step",
		goal,
		prompt: goal,
		child_ids: [],
		branch_rules: [],
		loop_config: null,
		agent_config: null,
		output_schema: null,
	};
}

const flowTemplates = [
	{
		id: "implement_review",
		slug: "implement_review",
		name: "Implement & Review",
		description:
			"Linear flow: research the codebase, implement changes, write tests, then review the result.",
		initial_node_id: "research",
		nodes: [
			stepNode("research", "Research the codebase", "Explore the relevant codebase areas and existing patterns."),
			stepNode("implement", "Implement the changes", "Make the required code changes following the discovered patterns."),
			stepNode("test", "Write and run tests", "Create tests that validate the implementation and run them."),
			stepNode("review", "Review the result", "Review all changes, check edge cases and code quality."),
		],
		transitions: [
			{ id: "t1", from_id: "research", to_id: "implement", condition: null, label: null },
			{ id: "t2", from_id: "implement", to_id: "test", condition: null, label: null },
			{ id: "t3", from_id: "test", to_id: "review", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "bugfix",
		slug: "bugfix",
		name: "Bug Fix",
		description:
			"Linear flow: reproduce the bug, diagnose the root cause, implement a fix, then verify.",
		initial_node_id: "reproduce",
		nodes: [
			stepNode("reproduce", "Reproduce the bug", "Create a minimal reproduction and confirm the failure mode."),
			stepNode("diagnose", "Diagnose root cause", "Trace the code to identify the root cause."),
			stepNode("fix", "Implement the fix", "Write a targeted fix for the identified root cause."),
			stepNode("verify", "Verify the fix", "Run the reproduction and related tests to confirm no regressions."),
		],
		transitions: [
			{ id: "t1", from_id: "reproduce", to_id: "diagnose", condition: null, label: null },
			{ id: "t2", from_id: "diagnose", to_id: "fix", condition: null, label: null },
			{ id: "t3", from_id: "fix", to_id: "verify", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "refactor_loop",
		slug: "refactor_loop",
		name: "Refactor Loop",
		description:
			"Loop-based flow: refactor a file and run tests until they pass (max 50 iterations).",
		initial_node_id: "identify_file",
		nodes: [
			stepNode("identify_file", "Identify file to refactor", "Determine which file needs refactoring."),
			{
				id: "refactor_loop",
				name: "Refactor & Test Loop",
				node_type: "loop",
				goal: "Refactor the file and run tests until all tests pass",
				prompt: null,
				child_ids: ["refactor_file", "run_tests"],
				branch_rules: [],
				loop_config: {
					max_iterations: 50,
					exit_condition: "tests_pass",
					child_ids: ["refactor_file", "run_tests"],
				},
				agent_config: null,
				output_schema: null,
			},
			stepNode("refactor_file", "Refactor the file", "Extract functions, simplify logic, improve naming."),
			stepNode("run_tests", "Run the test suite", "Run the suite and set tests_pass=true when green."),
			stepNode("summarize", "Summarize refactoring", "Summarize what changed and the final test status."),
		],
		transitions: [
			{ id: "t1", from_id: "identify_file", to_id: "refactor_loop", condition: null, label: null },
			{ id: "t2", from_id: "refactor_loop", to_id: "summarize", condition: "loop_exit", label: "loop_exit" },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "review_gate",
		slug: "review_gate",
		name: "Review Gate",
		description:
			"Branching flow: approve to finish, request changes to fix and re-review, or reject to roll back.",
		initial_node_id: "review",
		nodes: [
			stepNode("review", "Review the changes", "Examine the changes for correctness and code quality."),
			{
				id: "gate_branch",
				name: "Approval Gate",
				node_type: "branch",
				goal: "Route on the review decision",
				prompt: null,
				child_ids: [],
				branch_rules: [
					{ condition: "approved", target_id: "done" },
					{ condition: "changes_requested", target_id: "fix" },
					{ condition: "rejected", target_id: "rollback" },
				],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
			stepNode("done", "Mark as approved", "Mark the task as complete."),
			stepNode("fix", "Address review comments", "Make targeted changes for each comment."),
			stepNode("re_review", "Re-review after fixes", "Verify all review comments were addressed."),
			stepNode("rollback", "Rollback changes", "Revert the changes and document the reason."),
		],
		transitions: [
			{ id: "t1", from_id: "review", to_id: "gate_branch", condition: null, label: null },
			{ id: "t2", from_id: "gate_branch", to_id: "done", condition: "approved", label: "approved" },
			{ id: "t3", from_id: "gate_branch", to_id: "fix", condition: "changes_requested", label: "changes requested" },
			{ id: "t4", from_id: "gate_branch", to_id: "rollback", condition: "rejected", label: "rejected" },
			{ id: "t5", from_id: "fix", to_id: "re_review", condition: null, label: null },
			{ id: "t6", from_id: "re_review", to_id: "gate_branch", condition: null, label: "re-evaluate" },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "multi_file_analysis",
		slug: "multi_file_analysis",
		name: "Multi-File Analysis",
		description:
			"Parallel flow: analyze multiple files concurrently, then synthesize a unified report.",
		initial_node_id: "identify_files",
		nodes: [
			stepNode("identify_files", "Identify files to analyze", "Determine which files need analysis."),
			{
				id: "parallel_analysis",
				name: "Parallel File Analysis",
				node_type: "parallel",
				goal: "Analyze multiple files concurrently",
				prompt: null,
				child_ids: ["analyze_file_a", "analyze_file_b", "analyze_file_c"],
				branch_rules: [],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
			stepNode("analyze_file_a", "Analyze file A", "Check structure, dependencies and issues."),
			stepNode("analyze_file_b", "Analyze file B", "Check structure, dependencies and issues."),
			stepNode("analyze_file_c", "Analyze file C", "Check structure, dependencies and issues."),
			stepNode("synthesize", "Synthesize findings", "Combine results into a unified report."),
		],
		transitions: [
			{ id: "t1", from_id: "identify_files", to_id: "parallel_analysis", condition: null, label: null },
			{ id: "t2", from_id: "parallel_analysis", to_id: "synthesize", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "design_implement",
		slug: "design_implement",
		name: "Design & Implement",
		description:
			"Human-in-the-loop flow: research, design, get approval, implement, then test.",
		initial_node_id: "research",
		nodes: [
			stepNode("research", "Research requirements", "Understand requirements and constraints."),
			stepNode("design", "Design the solution", "Write a design document with approach and trade-offs."),
			{
				id: "design_review",
				name: "Design Review",
				node_type: "human_input",
				goal: "Get human approval on the design before implementation",
				prompt: "Review the proposed design. Reply 'approve' to proceed or give feedback.",
				child_ids: [],
				branch_rules: [],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
			stepNode("implement", "Implement the solution", "Implement the approved design."),
			stepNode("test", "Test the implementation", "Write and run tests validating the design."),
		],
		transitions: [
			{ id: "t1", from_id: "research", to_id: "design", condition: null, label: null },
			{ id: "t2", from_id: "design", to_id: "design_review", condition: null, label: null },
			{ id: "t3", from_id: "design_review", to_id: "implement", condition: null, label: null },
			{ id: "t4", from_id: "implement", to_id: "test", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
];

const templatesBySlug = new Map(flowTemplates.map((t) => [t.slug, t]));

function templateSummary(template) {
	return {
		id: template.id,
		slug: template.slug,
		name: template.name,
		description: template.description,
		initial_node_id: template.initial_node_id,
		nodes: template.nodes,
		transitions: template.transitions,
		node_count: template.nodes.length,
		transition_count: template.transitions.length,
		on_done_template_id: template.on_done_template_id,
		on_reject_template_id: template.on_reject_template_id,
	};
}

/** Step records for a task's flow, derived from its template so the graph and
 * history agree: nodes before the current one completed, the current one in
 * flight (or all completed once the task is done). */
function flowSteps(task, template) {
	const nodes = template.nodes.filter(
		(node) => node.node_type === "step" || node.node_type === "human_input",
	);
	const completed = task.status === "done" || task.current_node_id === null;
	const currentIndex = task.current_node_id
		? nodes.findIndex((node) => node.id === task.current_node_id)
		: -1;
	return nodes.map((node, index) => {
		const isCurrent = !completed && index === currentIndex;
		const done = completed || (currentIndex >= 0 && index < currentIndex);
		const createdAt = NOW - (nodes.length - index) * 120;
		return {
			id: `ex-${task.id}-${node.id}`,
			node_id: node.id,
			status: done ? "completed" : isCurrent ? "in_progress" : "pending",
			prompt: node.prompt,
			output: done ? `${node.name} completed` : null,
			transition_result: null,
			model: done || isCurrent ? "claude-sonnet-4" : null,
			input_tokens: done ? 1200 : 0,
			output_tokens: done ? 220 : 0,
			cost: done ? 0.022 : 0,
			duration_ms: done ? 5330 : 0,
			created_at: createdAt,
			completed_at: done ? createdAt + 6 : null,
		};
	});
}

/** Execution state for a task's bound flow, or null when none is bound. */
function flowStateForTask(task) {
	if (!task || !task.flow_instance_id) return null;
	const template = templatesBySlug.get(task.flow_template_id);
	if (!template) return null;
	const keys = flowSteps(task, template);
	const current = task.current_node_id
		? template.nodes.find((node) => node.id === task.current_node_id)
		: undefined;
	const status =
		task.status === "done" || !current
			? "completed"
			: current.node_type === "human_input"
				? "awaiting_input"
				: "running";
	return {
		id: `state-${task.id}`,
		task_id: task.id,
		status,
		current_node_id: task.current_node_id,
		flow_instance: {
			id: task.flow_instance_id,
			template_id: template.slug,
			task_id: task.id,
			nodes: template.nodes,
			transitions: template.transitions,
			initial_node_id: template.initial_node_id,
			on_done_template_id: template.on_done_template_id,
			on_reject_template_id: template.on_reject_template_id,
		},
		step_history: keys,
		loop_counters: {},
		variables: {},
	};
}

/** Terminal workflow statuses: a blocker in one of these no longer blocks. */
function isTerminalStatus(status) {
	return status === "done" || status === "cancelled";
}

/** A task is ready when it is neither archived nor in a terminal workflow state
 * and every one of its blockers has reached a terminal state. */
function isReadyTask(task) {
	if (task.archived || isTerminalStatus(task.status)) return false;
	const blockers = blockedBy.get(task.id);
	if (!blockers || blockers.size === 0) return true;
	return [...blockers].every((id) => {
		const blocker = tasks.find((candidate) => candidate.id === id);
		return !blocker || isTerminalStatus(blocker.status);
	});
}

/** Incomplete blockers only — terminal blockers are filtered out (C6). */
function incompleteBlockers(taskId) {
	const blockers = blockedBy.get(taskId);
	if (!blockers) return [];
	return [...blockers]
		.map((id) => tasks.find((candidate) => candidate.id === id))
		.filter((task) => task && !isTerminalStatus(task.status));
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function pageItems(items, limit, beforeSequence) {
	const newestFirst = [...items].sort((a, b) => b.sequence - a.sequence);
	const window =
		beforeSequence === undefined
			? newestFirst
			: newestFirst.filter((item) => item.sequence < beforeSequence);
	const page = window.slice(0, limit);
	const last = page.length > 0 ? page[page.length - 1].sequence : -Infinity;
	const hasMore = window.some((item) => item.sequence < last);
	return { page, hasMore };
}

function executionTotals(items) {
	return items.reduce(
		(acc, item) => {
			acc.total_input_tokens += item.input_tokens;
			acc.total_output_tokens += item.output_tokens;
			acc.total_cost += item.cost;
			acc.total_duration_ms += item.duration_ms;
			return acc;
		},
		{
			total_input_tokens: 0,
			total_output_tokens: 0,
			total_cost: 0,
			total_duration_ms: 0,
		},
	);
}

function errorBody(code, message) {
	return JSON.stringify({ error: code, message });
}

// ─── HTTP server ────────────────────────────────────────────────────────────

function route(req) {
	const url = new URL(req.url, "http://localhost");
	const segments = url.pathname.split("/").filter(Boolean);
	const query = url.searchParams;
	const limit = Number(query.get("limit") || 50);
	const beforeRaw = query.get("before_sequence");
	const beforeSequence =
		beforeRaw === null || beforeRaw === "" ? undefined : Number(beforeRaw);

	if (req.method === "GET" && url.pathname === "/health") {
		return { status: 200, body: JSON.stringify({ status: "ok", version, db }) };
	}

	if (req.method === "GET" && url.pathname === "/") {
		return { status: 200, body: JSON.stringify({ status: "ok", version, db }) };
	}

	const [api, v1, ...rest] = segments;
	if (api !== "api" || v1 !== "v1") {
		return { status: 404, body: errorBody("not_found", url.pathname) };
	}

	// GET /api/v1/tasks — flat list for the task pickers.
	if (req.method === "GET" && rest.length === 1 && rest[0] === "tasks") {
		return { status: 200, body: JSON.stringify(tasks) };
	}

	// GET /api/v1/tasks/ready — unblocked, non-terminal tasks.
	if (req.method === "GET" && rest.length === 2 && rest[0] === "tasks" && rest[1] === "ready") {
		return { status: 200, body: JSON.stringify(tasks.filter(isReadyTask)) };
	}

	// GET /api/v1/flow-templates — the prebuilt template registry.
	if (req.method === "GET" && rest.length === 1 && rest[0] === "flow-templates") {
		return {
			status: 200,
			body: JSON.stringify({ templates: flowTemplates.map(templateSummary) }),
		};
	}

	// GET /api/v1/flow-templates/:id — one template by id or slug.
	if (req.method === "GET" && rest.length === 2 && rest[0] === "flow-templates") {
		const template =
			templatesBySlug.get(rest[1]) ??
			flowTemplates.find((candidate) => candidate.id === rest[1]);
		return template
			? { status: 200, body: JSON.stringify(templateSummary(template)) }
			: {
					status: 404,
					body: errorBody("not_found", `flow template ${rest[1]}`),
				};
	}

	// GET /api/v1/tasks/:id
	if (req.method === "GET" && rest.length === 2 && rest[0] === "tasks") {
		const task = tasks.find((candidate) => candidate.id === rest[1]);
		return task
			? { status: 200, body: JSON.stringify(task) }
			: { status: 404, body: errorBody("not_found", `task ${rest[1]}`) };
	}

	// GET /api/v1/tasks/:id/flow — the task's current flow execution state.
	if (
		req.method === "GET" &&
		rest.length === 3 &&
		rest[0] === "tasks" &&
		rest[2] === "flow"
	) {
		const task = tasks.find((candidate) => candidate.id === rest[1]);
		if (!task) {
			return { status: 404, body: errorBody("not_found", `task ${rest[1]}`) };
		}
		const state = flowStateForTask(task);
		return state
			? { status: 200, body: JSON.stringify(state) }
			: {
					status: 404,
					body: errorBody("not_found", `flow for task ${rest[1]}`),
				};
	}

	// GET /api/v1/tasks/:id/blockers — incomplete blockers only.
	if (
		req.method === "GET" &&
		rest.length === 3 &&
		rest[0] === "tasks" &&
		rest[2] === "blockers"
	) {
		const task = tasks.find((candidate) => candidate.id === rest[1]);
		if (!task) {
			return { status: 404, body: errorBody("not_found", `task ${rest[1]}`) };
		}
		return { status: 200, body: JSON.stringify(incompleteBlockers(task.id)) };
	}

	// POST /api/v1/tasks/:id/dependencies — add a blocker ({ depends_on }).
	if (
		req.method === "POST" &&
		rest.length === 3 &&
		rest[0] === "tasks" &&
		rest[2] === "dependencies"
	) {
		const task = tasks.find((candidate) => candidate.id === rest[1]);
		if (!task) {
			return { status: 404, body: errorBody("not_found", `task ${rest[1]}`) };
		}
		let data = {};
		try {
			data = JSON.parse(req.body || "{}");
		} catch {
			data = {};
		}
		const dependsOn = data.depends_on;
		if (typeof dependsOn !== "string" || !tasks.some((t) => t.id === dependsOn)) {
			return {
				status: 422,
				body: errorBody("invalid_dependency", `unknown task ${dependsOn}`),
			};
		}
		if (dependsOn === task.id) {
			return {
				status: 422,
				body: errorBody("invalid_dependency", "a task cannot block itself"),
			};
		}
		const blockers = blockedBy.get(task.id) ?? new Set();
		blockers.add(dependsOn);
		blockedBy.set(task.id, blockers);
		return { status: 201, body: JSON.stringify({ blocked_by: [...blockers] }) };
	}

	// DELETE /api/v1/tasks/:id/dependencies/:depends_on — remove a blocker.
	if (
		req.method === "DELETE" &&
		rest.length === 4 &&
		rest[0] === "tasks" &&
		rest[2] === "dependencies"
	) {
		const task = tasks.find((candidate) => candidate.id === rest[1]);
		if (!task) {
			return { status: 404, body: errorBody("not_found", `task ${rest[1]}`) };
		}
		const blockers = blockedBy.get(task.id);
		if (!blockers || !blockers.delete(rest[3])) {
			return {
				status: 404,
				body: errorBody("not_found", `dependency ${rest[3]}`),
			};
		}
		return { status: 200, body: JSON.stringify({ blocked_by: [...blockers] }) };
	}

	// GET /api/v1/tasks/:id/executions
	if (
		req.method === "GET" &&
		rest.length === 3 &&
		rest[0] === "tasks" &&
		rest[2] === "executions"
	) {
		const taskId = rest[1];
		const items = executionsByTask[taskId];
		if (!items) {
			return { status: 404, body: errorBody("not_found", `task ${taskId}`) };
		}
		const { page, hasMore } = pageItems(items, limit, beforeSequence);
		const body = JSON.stringify({
			executions: page,
			has_more: hasMore,
			aggregate: executionTotals(items),
		});
		return { status: 200, body };
	}

	// GET /api/v1/executions/active
	if (
		req.method === "GET" &&
		rest.length === 2 &&
		rest[0] === "executions" &&
		rest[1] === "active"
	) {
		const active = Object.values(executionsByTask)
			.flat()
			.filter(
				(item) =>
					item.status === "in_progress" || item.status === "awaiting_input",
			)
			.sort((a, b) => b.sequence - a.sequence)
			.slice(0, limit);
		return {
			status: 200,
			body: JSON.stringify({ executions: active, has_more: false }),
		};
	}

	// GET /api/v1/executions/:id
	if (req.method === "GET" && rest.length === 2 && rest[0] === "executions") {
		const execution = Object.values(executionsByTask)
			.flat()
			.find((candidate) => candidate.id === rest[1]);
		return execution
			? { status: 200, body: JSON.stringify(execution) }
			: { status: 404, body: errorBody("not_found", `execution ${rest[1]}`) };
	}

	// GET /api/v1/executions/:id/logs — newest first, cursor = oldest of the page.
	if (
		req.method === "GET" &&
		rest.length === 3 &&
		rest[0] === "executions" &&
		rest[2] === "logs"
	) {
		const execId = rest[1];
		const items = logsByExecution[execId];
		if (!items) {
			return {
				status: 404,
				body: errorBody("not_found", `execution ${execId}`),
			};
		}
		const { page, hasMore } = pageItems(items, limit, beforeSequence);
		return {
			status: 200,
			body: JSON.stringify({ events: page, has_more: hasMore }),
		};
	}

	// POST /api/v1/executions/:id/logs — append an event (harness / manual use).
	if (
		req.method === "POST" &&
		rest.length === 3 &&
		rest[0] === "executions" &&
		rest[2] === "logs"
	) {
		const execId = rest[1];
		let data = {};
		try {
			data = JSON.parse(req.body || "{}");
		} catch {
			data = {};
		}
		const items = logsByExecution[execId];
		if (!items) {
			return {
				status: 404,
				body: errorBody("not_found", `execution ${execId}`),
			};
		}
		const event = logEvent(
			`ev-${execId}-${items.length + 1}`,
			execId,
			items[0]?.task_id ?? "",
			data.event_type || "text",
			data.payload,
			items.length + 1,
			NOW,
		);
		items.push(event);
		return { status: 201, body: JSON.stringify(event) };
	}

	return { status: 404, body: errorBody("not_found", url.pathname) };
}

const server = http.createServer((req, res) => {
	// CORS preflight: answer before routing so every cross-origin fetch works.
	if (req.method === "OPTIONS") {
		res.writeHead(204, { ...CORS_HEADERS, "content-length": 0 });
		res.end();
		return;
	}
	const chunks = [];
	req.on("data", (chunk) => chunks.push(chunk));
	req.on("end", () => {
		req.body = Buffer.concat(chunks).toString("utf8");
		const { status, body } = route(req);
		res.writeHead(status, {
			"content-type": "application/json",
			"content-length": Buffer.byteLength(body),
			...CORS_HEADERS,
		});
		res.end(body);
	});
});

server.listen(port, "127.0.0.1", () => {
	process.stderr.write(
		`[crystalline-stub] listening on http://127.0.0.1:${port}\n`,
	);
});

function shutdown() {
	process.stderr.write("[crystalline-stub] shutting down\n");
	server.close(() => process.exit(0));
	// Safety net if connections keep the server open.
	setTimeout(() => process.exit(0), 2000).unref();
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
