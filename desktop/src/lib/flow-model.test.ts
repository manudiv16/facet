// facet#10 tests for the C18 execution envelope.
//
// `GET/POST /api/v1/tasks/:id/flow` answer `{instance, execution}`: the graph
// lives under `instance` and the runtime state under `execution`. Reading the
// runtime fields from the envelope root used to leave every execution at
// `pending` with the node highlight lost, so both the envelope and the older
// shapes are pinned here.

import { describe, expect, it } from "vitest";
import { normalizeAdvance, normalizeState } from "./flow-model";

const NODE = {
	id: "research",
	name: "Research",
	node_type: "step",
	goal: "Look around",
	prompt: "Look around",
	child_ids: [],
	branch_rules: [],
	loop_config: null,
	agent_config: null,
	output_schema: null,
};

/** Raw wire payload of `instantiate`/`get_task_flow` (flows.gleam). */
function envelope(overrides: Record<string, unknown> = {}) {
	return {
		instance: {
			id: "flow-1",
			template_id: "tpl-1",
			task_id: "task-1",
			initial_node_id: "research",
			nodes: [NODE],
			transitions: [],
			on_done_template_id: null,
			on_reject_template_id: null,
		},
		execution: {
			id: "exec-1",
			instance_id: "flow-1",
			task_id: "task-1",
			status: "running",
			current_node_id: "research",
			started_at: 1_751_234_567_000,
			completed_at: null,
		},
		...overrides,
	};
}

describe("normalizeState", () => {
	it("reads runtime state from `execution` and the graph from `instance`", () => {
		const state = normalizeState(envelope());

		expect(state.id).toBe("exec-1");
		expect(state.status).toBe("running");
		expect(state.current_node_id).toBe("research");
		expect(state.started_at).toBe(1_751_234_567_000);
		expect(state.completed_at).toBeNull();
		expect(state.task_id).toBe("task-1");
		expect(state.flow_instance.id).toBe("flow-1");
		expect(state.flow_instance.template_id).toBe("tpl-1");
		expect(state.flow_instance.nodes.map((node) => node.id)).toEqual([
			"research",
		]);
	});

	it("keeps a pending instantiation pending", () => {
		const state = normalizeState(
			envelope({
				execution: {
					id: "exec-2",
					instance_id: "flow-1",
					task_id: "task-1",
					status: "pending",
					current_node_id: null,
					started_at: null,
					completed_at: null,
				},
			}),
		);

		expect(state.status).toBe("pending");
		expect(state.current_node_id).toBeNull();
	});

	it("still reads the older `{state, instance}` shape", () => {
		const state = normalizeState({
			state: {
				id: "exec-9",
				status: "awaiting_input",
				current_node_id: "research",
				started_at: 1_751_234_567_000,
			},
			instance: envelope().instance,
		});

		expect(state.status).toBe("awaiting_input");
		expect(state.current_node_id).toBe("research");
		expect(state.flow_instance.id).toBe("flow-1");
	});

	it("reads a flat execution-only payload without inventing an instance", () => {
		const state = normalizeState({
			id: "exec-3",
			status: "rejected",
			current_node_id: "research",
			completed_at: 1_751_234_999_000,
		});

		expect(state.status).toBe("rejected");
		expect(state.completed_at).toBe(1_751_234_999_000);
		expect(state.flow_instance.id).toBe("");
	});
});

describe("normalizeAdvance", () => {
	it("normalises the engine's `{execution, action}` answer", () => {
		const result = normalizeAdvance({
			execution: envelope().execution,
			action: {
				type: "run_step",
				node: NODE,
				prompt: "Look around",
			},
		});

		expect(result.action?.kind).toBe("run_step");
		expect(result.action?.node?.id).toBe("research");
		expect(result.action?.prompt).toBe("Look around");
		// The action payload carries no graph, so no state is fabricated here;
		// the flow store refreshes from the task's flow resource instead.
		expect(result.state).toBeNull();
	});
});
