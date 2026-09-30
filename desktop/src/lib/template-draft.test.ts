// facet#10 tests for the editor draft conversion.
//
// The editor is the only writer of create/update bodies, so the conversion has
// to be lossless in both directions: a template opened for editing and saved
// unchanged must produce the same graph (including `agent_config`, which the
// form does not edit), and every row the engine's decoders need must be present.

import { describe, expect, it } from "vitest";
import {
	emptyNodeDraft,
	emptyTemplateDraft,
	emptyTransitionDraft,
	parseBranchRules,
	parseIdList,
	nodeDraftFromNode,
	templateDraftFromTemplate,
	templateInputFromDraft,
	type TemplateDraft,
} from "./template-draft";
import type { FlowTemplate, FlowNode } from "./types";

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

function draftFor(overrides: Partial<TemplateDraft> = {}): TemplateDraft {
	return {
		id: null,
		name: "Custom",
		description: "d",
		initialNodeId: "implement",
		onDoneTemplateId: "",
		onRejectTemplateId: "",
		nodes: [],
		transitions: [],
		...overrides,
	};
}

describe("parseIdList", () => {
	it("splits on commas and newlines and drops blanks", () => {
		expect(parseIdList(" a, b ,,\nc ")).toEqual(["a", "b", "c"]);
		expect(parseIdList("   ")).toEqual([]);
	});

	it("keeps ids that contain spaces", () => {
		expect(parseIdList("first node, second node")).toEqual([
			"first node",
			"second node",
		]);
	});
});

describe("parseBranchRules", () => {
	it("parses one rule per line", () => {
		expect(parseBranchRules("approved => done\nrejected => fix", "gate")).toEqual([
			{ condition: "approved", target_id: "done" },
			{ condition: "rejected", target_id: "fix" },
		]);
	});

	it("names the node when a line has no separator", () => {
		expect(() => parseBranchRules("approved", "gate")).toThrow(/gate.*=>/);
	});
});

describe("templateInputFromDraft", () => {
	it("emits the loop config for loop nodes and nulls for the rest", () => {
		const input = templateInputFromDraft(
			draftFor({
				nodes: [
					{
						...emptyNodeDraft("implement"),
						name: "Implement",
						goal: "Make the change",
					},
					{
						...emptyNodeDraft("iterate"),
						name: "Iterate",
						node_type: "loop",
						childIds: "implement, review",
						loopMaxIterations: "3",
						loopExitCondition: "approved",
					},
				],
			}),
		);

		expect(input.initial_node_id).toBe("implement");
		expect(input.nodes[0]).toMatchObject({
			id: "implement",
			name: "Implement",
			node_type: "step",
			prompt: null,
			child_ids: [],
			loop_config: null,
		});
		expect(input.nodes[1]).toMatchObject({
			id: "iterate",
			node_type: "loop",
			child_ids: ["implement", "review"],
			loop_config: {
				max_iterations: 3,
				exit_condition: "approved",
				child_ids: ["implement", "review"],
			},
		});
	});

	it("parses branch rules and optional ids, and drops fully blank rows", () => {
		const input = templateInputFromDraft(
			draftFor({
				onDoneTemplateId: "  ",
				onRejectTemplateId: "gate_reject",
				nodes: [
					{
						...emptyNodeDraft("gate"),
						node_type: "branch",
						branchRules: "approved => done\nrejected => fix",
					},
					emptyNodeDraft(""),
				],
				transitions: [
					{ ...emptyTransitionDraft(), id: "t-1", fromId: "a", toId: "b" },
					emptyTransitionDraft(),
				],
			}),
		);

		expect(input.nodes).toHaveLength(1);
		expect(input.nodes[0].branch_rules).toEqual([
			{ condition: "approved", target_id: "done" },
			{ condition: "rejected", target_id: "fix" },
		]);
		expect(input.on_done_template_id).toBeNull();
		expect(input.on_reject_template_id).toBe("gate_reject");
		expect(input.transitions).toEqual([
			{ id: "t-1", from_id: "a", to_id: "b", condition: null, label: null },
		]);
	});

	it("rejects a filled row without an id or a target", () => {
		expect(() =>
			templateInputFromDraft(
				draftFor({ nodes: [{ ...emptyNodeDraft(""), goal: "orphan" }] }),
			),
		).toThrow(/needs an id/);

		expect(() =>
			templateInputFromDraft(
				draftFor({
					transitions: [
						{ ...emptyTransitionDraft(), id: "t-1", fromId: "a" },
					],
				}),
			),
		).toThrow(/from_id and a to_id/);
	});

	it("round-trips a stored template without losing its graph", () => {
		const template: FlowTemplate = {
			id: "tpl-1",
			slug: "tpl-1",
			name: "Review gate",
			description: "branch-mediated",
			initial_node_id: "gate",
			nodes: [
				stepNode({
					id: "gate",
					name: "Gate",
					node_type: "branch",
					prompt: null,
					branch_rules: [{ condition: "approved", target_id: "done" }],
				}),
				stepNode({ id: "done", name: "Done", prompt: "Wrap up" }),
				stepNode({
					id: "agent",
					name: "Agent",
					prompt: "Do it",
					output_schema: '{"type":"object"}',
					agent_config: {
						model: "claude-sonnet-4",
						fallback_model: null,
						system_prompt: "be terse",
						allowed_tools: ["read"],
						disallowed_tools: [],
						permission_mode: "default",
						max_budget_usd: 1.5,
					},
				}),
			],
			transitions: [
				{ id: "t-1", from_id: "gate", to_id: "done", condition: "ok", label: "yes" },
			],
			on_done_template_id: "tpl-next",
			on_reject_template_id: null,
		};

		const draft = templateDraftFromTemplate(template);
		const input = templateInputFromDraft(draft);

		expect(input.name).toBe(template.name);
		expect(input.initial_node_id).toBe(template.initial_node_id);
		expect(input.on_done_template_id).toBe("tpl-next");
		expect(input.nodes).toEqual(
			template.nodes.map((node) =>
				expect.objectContaining({
					id: node.id,
					name: node.name,
					node_type: node.node_type,
					goal: node.goal,
					prompt: node.prompt,
					child_ids: node.child_ids,
					branch_rules: node.branch_rules,
					agent_config: node.agent_config,
					output_schema: node.output_schema,
				}),
			),
		);
		expect(input.transitions).toEqual(template.transitions);
	});

	it("keeps a node that only has an id, so a half-typed row is not dropped", () => {
		const input = templateInputFromDraft(
			draftFor({ nodes: [nodeDraftFromNode(stepNode({ id: "implement" }))] }),
		);
		expect(input.nodes).toHaveLength(1);
		expect(input.nodes[0].id).toBe("implement");
	});
});
