// Authoring drafts — the string-shaped form state behind the template editor,
// converted to and from the canonical shapes in `types.ts`.
//
// The editor edits a `TemplateDraft` (text inputs for ids, comma-separated
// child lists and one branch rule per line); `templateInputFromDraft` turns it
// into the create/update body and throws a user-facing `Error` for rows the
// engine's decoders would otherwise reject with an opaque 400.

import type { FlowTemplateInput } from "./flow-templates-api";
import type {
	AgentConfig,
	BranchRule,
	FlowNode,
	FlowNodeType,
	FlowTemplate,
	FlowTransition,
} from "./types";

/** One node row in the editor form. */
export interface NodeDraft {
	id: string;
	name: string;
	node_type: FlowNodeType;
	goal: string;
	prompt: string;
	/** Comma-separated child ids (also the Loop iteration set). */
	childIds: string;
	/** One `condition => target_id` per line. */
	branchRules: string;
	loopMaxIterations: string;
	loopExitCondition: string;
	outputSchema: string;
	/** Not editable here; preserved verbatim across a PATCH. */
	agentConfig: AgentConfig | null;
}

/** One transition row: edited in the create form, sub-resource managed otherwise. */
export interface TransitionDraft {
	id: string;
	fromId: string;
	toId: string;
	condition: string;
	label: string;
}

export interface TemplateDraft {
	/** `null` while creating; the server id once persisted. */
	id: string | null;
	name: string;
	description: string;
	initialNodeId: string;
	onDoneTemplateId: string;
	onRejectTemplateId: string;
	nodes: NodeDraft[];
	transitions: TransitionDraft[];
}

export function emptyNodeDraft(id = ""): NodeDraft {
	return {
		id,
		name: "",
		node_type: "step",
		goal: "",
		prompt: "",
		childIds: "",
		branchRules: "",
		loopMaxIterations: "",
		loopExitCondition: "",
		outputSchema: "",
		agentConfig: null,
	};
}

export function emptyTransitionDraft(): TransitionDraft {
	return { id: "", fromId: "", toId: "", condition: "", label: "" };
}

export function emptyTemplateDraft(): TemplateDraft {
	return {
		id: null,
		name: "",
		description: "",
		initialNodeId: "",
		onDoneTemplateId: "",
		onRejectTemplateId: "",
		nodes: [emptyNodeDraft("start")],
		transitions: [],
	};
}

export function nodeDraftFromNode(node: FlowNode): NodeDraft {
	return {
		id: node.id,
		name: node.name,
		node_type: node.node_type,
		goal: node.goal,
		prompt: node.prompt ?? "",
		childIds: node.child_ids.join(", "),
		branchRules: node.branch_rules
			.map((rule) => `${rule.condition} => ${rule.target_id}`)
			.join("\n"),
		loopMaxIterations:
			node.loop_config?.max_iterations != null
				? String(node.loop_config.max_iterations)
				: "",
		loopExitCondition: node.loop_config?.exit_condition ?? "",
		outputSchema: node.output_schema ?? "",
		agentConfig: node.agent_config ?? null,
	};
}

export function transitionDraftFromTransition(
	transition: FlowTransition,
): TransitionDraft {
	return {
		id: transition.id,
		fromId: transition.from_id,
		toId: transition.to_id,
		condition: transition.condition ?? "",
		label: transition.label ?? "",
	};
}

export function templateDraftFromTemplate(template: FlowTemplate): TemplateDraft {
	return {
		id: template.id,
		name: template.name,
		description: template.description,
		initialNodeId: template.initial_node_id,
		onDoneTemplateId: template.on_done_template_id ?? "",
		onRejectTemplateId: template.on_reject_template_id ?? "",
		nodes: template.nodes.map(nodeDraftFromNode),
		transitions: template.transitions.map(transitionDraftFromTransition),
	};
}

/** Split a comma/newline-separated id list, dropping blanks. */
export function parseIdList(text: string): string[] {
	return text
		.split(/[,\n]/)
		.map((id) => id.trim())
		.filter((id) => id.length > 0);
}

/** Parse `condition => target_id` lines; a line without `=>` is an error. */
export function parseBranchRules(text: string, nodeId: string): BranchRule[] {
	const rules: BranchRule[] = [];
	const lines = text.split(/\n/);
	for (let index = 0; index < lines.length; index += 1) {
		const line = lines[index].trim();
		if (line.length === 0) continue;
		const separator = line.indexOf("=>");
		if (separator === -1) {
			throw new Error(
				`Node ${nodeId}: branch rule "${line}" is missing "=>" (use "condition => target")`,
			);
		}
		rules.push({
			condition: line.slice(0, separator).trim(),
			target_id: line.slice(separator + 2).trim(),
		});
	}
	return rules;
}

/** `""` → `null`, `"3"` → `3`, anything unparseable → `null` (treated as unbounded). */
function parseOptionalInt(text: string): number | null {
	const parsed = Number.parseInt(text.trim(), 10);
	return Number.isFinite(parsed) ? parsed : null;
}

/** A row counts as intentional once any of its identity fields is filled in. */
function hasIdentity(id: string, ...refs: string[]): boolean {
	return [id, ...refs].some((value) => value.trim().length > 0);
}

export function nodeFromDraft(draft: NodeDraft): FlowNode {
	const id = draft.id.trim();
	if (id.length === 0) {
		throw new Error("Every node needs an id");
	}
	const childIds = parseIdList(draft.childIds);
	const loopMaxIterations = parseOptionalInt(draft.loopMaxIterations);
	const loopExitCondition = draft.loopExitCondition.trim();
	return {
		id,
		name: draft.name.trim() || id,
		node_type: draft.node_type,
		goal: draft.goal.trim(),
		prompt: draft.prompt.trim().length > 0 ? draft.prompt : null,
		child_ids: childIds,
		branch_rules: parseBranchRules(draft.branchRules, id),
		loop_config:
			draft.node_type === "loop"
				? {
						max_iterations: loopMaxIterations,
						exit_condition: loopExitCondition || null,
						child_ids: childIds,
					}
				: null,
		agent_config: draft.agentConfig,
		output_schema: draft.outputSchema.trim() || null,
	};
}

export function transitionFromDraft(draft: TransitionDraft): FlowTransition {
	const id = draft.id.trim();
	const fromId = draft.fromId.trim();
	const toId = draft.toId.trim();
	if (id.length === 0 || fromId.length === 0 || toId.length === 0) {
		throw new Error("Every transition needs an id, a from_id and a to_id");
	}
	return {
		id,
		from_id: fromId,
		to_id: toId,
		condition: draft.condition.trim() || null,
		label: draft.label.trim() || null,
	};
}

/**
 * Convert the editor draft into a create/update body. Fully blank rows are
 * dropped; partially filled rows raise a user-facing error naming the row.
 */
export function templateInputFromDraft(draft: TemplateDraft): FlowTemplateInput {
	const nodes: FlowNode[] = [];
	for (const row of draft.nodes) {
		if (!hasIdentity(row.id, row.name, row.goal, row.prompt, row.childIds)) {
			continue;
		}
		nodes.push(nodeFromDraft(row));
	}
	const transitions: FlowTransition[] = [];
	for (const row of draft.transitions) {
		if (!hasIdentity(row.id, row.fromId, row.toId)) continue;
		transitions.push(transitionFromDraft(row));
	}
	return {
		name: draft.name.trim(),
		description: draft.description,
		initial_node_id: draft.initialNodeId.trim(),
		nodes,
		transitions,
		on_done_template_id: draft.onDoneTemplateId.trim() || null,
		on_reject_template_id: draft.onRejectTemplateId.trim() || null,
	};
}
