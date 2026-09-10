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
		flow_template_id: "linear",
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
		flow_template_id: "linear",
		flow_instance_id: "flow-2",
		current_node_id: "approve",
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
		flow_template_id: "loop",
		flow_instance_id: "flow-3",
		current_node_id: null,
		worktree: null,
		archived: false,
		created_at: NOW - 604800,
		updated_at: NOW - 86400,
	},
];

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

	// GET /api/v1/tasks/:id
	if (req.method === "GET" && rest.length === 2 && rest[0] === "tasks") {
		const task = tasks.find((candidate) => candidate.id === rest[1]);
		return task
			? { status: 200, body: JSON.stringify(task) }
			: { status: 404, body: errorBody("not_found", `task ${rest[1]}`) };
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
	const chunks = [];
	req.on("data", (chunk) => chunks.push(chunk));
	req.on("end", () => {
		req.body = Buffer.concat(chunks).toString("utf8");
		const { status, body } = route(req);
		res.writeHead(status, {
			"content-type": "application/json",
			"content-length": Buffer.byteLength(body),
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
