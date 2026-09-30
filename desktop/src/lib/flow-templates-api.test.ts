// facet#10 acceptance tests for the template authoring client.
//
// Covers the request bodies the engine's decoders actually require (every node
// field present, optionals `null` rather than absent), the 400/404/409
// rejections the authoring UI renders next to the form, and the transition
// sub-resource URLs.

import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
	get: vi.fn(),
	post: vi.fn(),
	patch: vi.fn(),
	delete: vi.fn(),
}));

vi.mock("./api", () => ({
	api: {
		get: mocks.get,
		post: mocks.post,
		patch: mocks.patch,
		delete: mocks.delete,
	},
}));

import {
	addTransition,
	classifyTemplateError,
	createTemplate,
	deleteTemplate,
	FlowTemplateError,
	getTemplate,
	listTemplates,
	listTransitions,
	removeTransition,
	toFlowTemplateError,
	updateTemplate,
} from "./flow-templates-api";
import type { FlowNode } from "./types";

beforeEach(() => {
	mocks.get.mockReset();
	mocks.post.mockReset();
	mocks.patch.mockReset();
	mocks.delete.mockReset();
});

/** Await a rejection as a typed failure; the test fails if it resolves. */
async function rejection(promise: Promise<unknown>): Promise<FlowTemplateError> {
	try {
		await promise;
	} catch (error) {
		return toFlowTemplateError(error);
	}
	throw new Error("expected the request to reject");
}

function stepNode(overrides: Partial<FlowNode> = {}): FlowNode {
	return {
		id: "implement",
		name: "Implement",
		node_type: "step",
		goal: "Make the change",
		prompt: "Implement the change",
		child_ids: [],
		branch_rules: [],
		loop_config: null,
		agent_config: null,
		output_schema: null,
		...overrides,
	};
}

/** Raw wire template, shaped exactly like `flow_templates_body/1`. */
function templateRaw(overrides: Record<string, unknown> = {}) {
	return {
		id: "tpl-1",
		name: "Custom",
		description: "two nodes",
		initial_node_id: "implement",
		nodes: [
			{
				id: "implement",
				name: "Implement",
				node_type: "step",
				goal: "Make the change",
				prompt: "Implement the change",
				child_ids: [],
				branch_rules: [],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
		],
		transitions: [
			{
				id: "t-1",
				from_id: "implement",
				to_id: "review",
				condition: null,
				label: null,
			},
		],
		on_done_template_id: null,
		on_reject_template_id: null,
		...overrides,
	};
}

describe("listTemplates / getTemplate", () => {
	it("hydrates each listed row from its detail endpoint", async () => {
		mocks.get.mockImplementation(async (endpoint: string) => {
			if (endpoint === "/api/v1/flow-templates") {
				// Registry list: counts only, no graph.
				return [
					{
						id: "tpl-1",
						slug: "tpl-1",
						name: "Custom",
						description: "two nodes",
						initial_node_id: "implement",
						node_count: 1,
						transition_count: 1,
					},
					{
						id: "tpl-2",
						slug: "tpl-2",
						name: "Second",
						description: "",
						initial_node_id: "implement",
						node_count: 1,
						transition_count: 1,
					},
				];
			}
			if (endpoint === "/api/v1/flow-templates/tpl-2") {
				return templateRaw({ id: "tpl-2", name: "Second" });
			}
			if (endpoint === "/api/v1/flow-templates/tpl-1") return templateRaw();
			throw { status: 404, message: "Flow template not found: " + endpoint };
		});

		const templates = await listTemplates();

		expect(mocks.get).toHaveBeenCalledWith("/api/v1/flow-templates");
		expect(mocks.get).toHaveBeenCalledWith("/api/v1/flow-templates/tpl-2");
		expect(templates.map((template) => template.id)).toEqual([
			"tpl-1",
			"tpl-2",
		]);
		expect(templates[0].slug).toBe("tpl-1");
		expect(templates[0].nodes.map((node) => node.id)).toEqual(["implement"]);
		expect(templates[0].transitions).toHaveLength(1);
		expect(templates[0].initial_node_id).toBe("implement");
	});

	it("keeps a listed row with its counts when its detail cannot be fetched", async () => {
		mocks.get.mockImplementation(async (endpoint: string) => {
			if (endpoint === "/api/v1/flow-templates") {
				return [
					{
						id: "tpl-9",
						name: "Counts only",
						description: "",
						initial_node_id: "a",
						node_count: 3,
						transition_count: 2,
					},
				];
			}
			throw { status: 500, message: "boom" };
		});

		const templates = await listTemplates();

		expect(templates[0].name).toBe("Counts only");
		expect(templates[0].node_count).toBe(3);
		expect(templates[0].transition_count).toBe(2);
		expect(templates[0].nodes).toEqual([]);
	});

	it("fetches a single template and surfaces an unknown id as a 404", async () => {
		mocks.get.mockResolvedValue(templateRaw());
		expect((await getTemplate("tpl-1")).name).toBe("Custom");
		expect(mocks.get).toHaveBeenCalledWith("/api/v1/flow-templates/tpl-1");

		mocks.get.mockRejectedValue({
			status: 404,
			message: "Flow template not found",
		});
		const failure = await rejection(getTemplate("nope"));
		expect(failure.status).toBe(404);
		expect(failure.message).toBe("Flow template not found");
		expect(classifyTemplateError(failure)).toBe("not_found");
	});
});

describe("createTemplate", () => {
	it("sends every field the node/transition decoders require", async () => {
		mocks.post.mockResolvedValue(templateRaw());

		await createTemplate({
			name: "Custom",
			description: "two nodes",
			initial_node_id: "implement",
			nodes: [
				stepNode(),
				stepNode({
					id: "review",
					name: "Review",
					prompt: null,
					loop_config: {
						max_iterations: 3,
						exit_condition: "approved",
						child_ids: ["implement"],
					},
				}),
			],
			transitions: [
				{
					id: "t-1",
					from_id: "implement",
					to_id: "review",
					condition: null,
					label: null,
				},
			],
			on_done_template_id: "tpl-done",
		});

		expect(mocks.post).toHaveBeenCalledWith("/api/v1/flow-templates", {
			name: "Custom",
			description: "two nodes",
			initial_node_id: "implement",
			nodes: [
				{
					id: "implement",
					name: "Implement",
					node_type: "step",
					goal: "Make the change",
					prompt: "Implement the change",
					child_ids: [],
					branch_rules: [],
					loop_config: null,
					agent_config: null,
					output_schema: null,
				},
				{
					id: "review",
					name: "Review",
					node_type: "step",
					goal: "Make the change",
					prompt: null,
					child_ids: [],
					branch_rules: [],
					loop_config: {
						max_iterations: 3,
						exit_condition: "approved",
						child_ids: ["implement"],
					},
					agent_config: null,
					output_schema: null,
				},
			],
			transitions: [
				{
					id: "t-1",
					from_id: "implement",
					to_id: "review",
					condition: null,
					label: null,
				},
			],
			on_done_template_id: "tpl-done",
			on_reject_template_id: null,
		});
	});

	it("keeps the engine's validator message when the graph is rejected", async () => {
		mocks.post.mockRejectedValue({
			status: 400,
			message:
				"Invalid flow template (1 validation error(s), first: cycle detected: a -> b -> a)",
		});

		const failure = await rejection(
			createTemplate({
				name: "Cyclic",
				initial_node_id: "a",
				nodes: [],
				transitions: [],
			}),
		);

		expect(failure.status).toBe(400);
		expect(failure.message).toContain("cycle detected: a -> b -> a");
		expect(classifyTemplateError(failure)).toBe("validation");
	});

	it("reports a request that never reached the engine as a network failure", async () => {
		mocks.post.mockRejectedValue({
			status: 0,
			message: "Crystalline is not connected yet",
		});

		const failure = await rejection(
			createTemplate({
				name: "Offline",
				initial_node_id: "a",
				nodes: [],
				transitions: [],
			}),
		);

		expect(failure.status).toBe(0);
		expect(failure.message).toBe("Crystalline is not connected yet");
		expect(classifyTemplateError(failure)).toBe("network");
	});
});

describe("updateTemplate", () => {
	it("PATCHes the full graph to the template id", async () => {
		mocks.patch.mockResolvedValue(templateRaw({ name: "Renamed" }));

		const updated = await updateTemplate("tpl-1", {
			name: "Renamed",
			initial_node_id: "implement",
			nodes: [stepNode()],
			transitions: [],
		});

		expect(mocks.patch).toHaveBeenCalledWith(
			"/api/v1/flow-templates/tpl-1",
			expect.objectContaining({
				name: "Renamed",
				initial_node_id: "implement",
				transitions: [],
			}),
		);
		expect(updated.name).toBe("Renamed");
	});
});

describe("deleteTemplate", () => {
	it("deletes and resolves for a 200", async () => {
		mocks.delete.mockResolvedValue({ message: "Deleted" });
		await expect(deleteTemplate("tpl-1")).resolves.toBeUndefined();
		expect(mocks.delete).toHaveBeenCalledWith("/api/v1/flow-templates/tpl-1");
	});

	it("surfaces the in-use conflict with the instance count", async () => {
		mocks.delete.mockRejectedValue({
			status: 409,
			message: "Flow template is in use by 2 instance(s)",
		});

		const failure = await rejection(deleteTemplate("tpl-1"));

		expect(failure.status).toBe(409);
		expect(failure.message).toBe("Flow template is in use by 2 instance(s)");
		expect(classifyTemplateError(failure)).toBe("conflict");
	});
});

describe("transition sub-resource", () => {
	it("lists the stored transitions", async () => {
		mocks.get.mockResolvedValue([
			{ id: "t-1", from_id: "a", to_id: "b", condition: "ok", label: "yes" },
		]);

		const transitions = await listTransitions("tpl-1");

		expect(mocks.get).toHaveBeenCalledWith(
			"/api/v1/flow-templates/tpl-1/transitions",
		);
		expect(transitions[0]).toEqual({
			id: "t-1",
			from_id: "a",
			to_id: "b",
			condition: "ok",
			label: "yes",
		});
	});

	it("POSTs one transition and rejects a duplicate id with 409", async () => {
		mocks.post.mockResolvedValue({
			id: "t-2",
			from_id: "a",
			to_id: "b",
			condition: null,
			label: null,
		});

		const added = await addTransition("tpl-1", {
			id: "t-2",
			from_id: "a",
			to_id: "b",
		});
		expect(mocks.post).toHaveBeenCalledWith(
			"/api/v1/flow-templates/tpl-1/transitions",
			{ id: "t-2", from_id: "a", to_id: "b", condition: null, label: null },
		);
		expect(added.id).toBe("t-2");

		mocks.post.mockRejectedValue({
			status: 409,
			message: "Transition already exists: t-2",
		});
		const failure = await rejection(
			addTransition("tpl-1", { id: "t-2", from_id: "a", to_id: "b" }),
		);
		expect(failure.status).toBe(409);
		expect(classifyTemplateError(failure)).toBe("conflict");
	});

	it("surfaces a dangling transition as the validator's 400", async () => {
		mocks.post.mockRejectedValue({
			status: 400,
			message:
				"Invalid flow template (1 validation error(s), first: transition t-3 references unknown node: ghost)",
		});

		const failure = await rejection(
			addTransition("tpl-1", { id: "t-3", from_id: "a", to_id: "ghost" }),
		);

		expect(failure.status).toBe(400);
		expect(failure.message).toContain("references unknown node: ghost");
	});

	it("DELETEs one transition by id and surfaces a removal that breaks the graph", async () => {
		mocks.delete.mockResolvedValue({ message: "Deleted" });
		await removeTransition("tpl-1", "t-2");
		expect(mocks.delete).toHaveBeenCalledWith(
			"/api/v1/flow-templates/tpl-1/transitions/t-2",
		);

		mocks.delete.mockRejectedValue({
			status: 400,
			message:
				"Invalid flow template (1 validation error(s), first: missing initial node: a)",
		});
		const failure = await rejection(removeTransition("tpl-1", "t-1"));
		expect(failure.status).toBe(400);
		expect(classifyTemplateError(failure)).toBe("validation");
	});
});
