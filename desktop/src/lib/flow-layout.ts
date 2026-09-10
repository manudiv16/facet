// Flow graph layout + status derivation.
//
// Pure functions with no Svelte or DOM dependencies so they can be unit
// tested and reused by any renderer. `computeLayout` produces a layered DAG
// layout (left → right) that is tolerant of cycles and disconnected nodes:
// back edges are detected with a DFS and ignored while layering, so a
// review-gate style flow (`re_review → gate_branch`) still lays out cleanly.

import type {
	FlowExecutionState,
	FlowNode,
	FlowNodeStatus,
	FlowNodeType,
	FlowTemplate,
	FlowTransition,
} from "./types";

export const NODE_WIDTH = 184;
export const NODE_HEIGHT = 88;
export const H_GAP = 96;
export const V_GAP = 44;
export const PADDING = 48;

export const NODE_TYPE_COLORS: Record<FlowNodeType, string> = {
	step: "#3b82f6", // blue
	sequence: "#8b5cf6", // violet
	branch: "#f59e0b", // amber
	loop: "#10b981", // emerald
	parallel: "#ec4899", // pink
	human_input: "#f97316", // orange
};

export const NODE_TYPE_ICONS: Record<FlowNodeType, string> = {
	step: "⚙",
	sequence: "≡",
	branch: "⑂",
	loop: "↻",
	parallel: "∥",
	human_input: "◉",
};

export const NODE_TYPE_LABELS: Record<FlowNodeType, string> = {
	step: "step",
	sequence: "sequence",
	branch: "branch",
	loop: "loop",
	parallel: "parallel",
	human_input: "human input",
};

export interface LayoutNode {
	node: FlowNode;
	x: number;
	y: number;
	layer: number;
	index: number;
}

export interface LayoutEdge {
	transition: FlowTransition;
	from: LayoutNode;
	to: LayoutNode;
	/** SVG path data (cubic Bézier). */
	path: string;
	labelX: number;
	labelY: number;
}

export interface FlowLayout {
	nodes: LayoutNode[];
	edges: LayoutEdge[];
	width: number;
	height: number;
}

// ─── Layering ────────────────────────────────────────────────────────────────

/**
 * Assign each node to a column. Uses longest-path layering over the DAG that
 * remains after back edges (detected via DFS) are removed. Every node gets a
 * layer, including disconnected ones, so no node silently disappears.
 */
export function computeLayers(
	nodes: FlowNode[],
	transitions: FlowTransition[],
	entryId: string,
): Map<string, number> {
	const layers = new Map<string, number>();
	if (nodes.length === 0) return layers;

	const nodeIds = new Set(nodes.map((node) => node.id));
	const adjacency = new Map<string, string[]>();
	for (const node of nodes) adjacency.set(node.id, []);

	const validTransitions = transitions.filter(
		(transition) =>
			nodeIds.has(transition.from_id) && nodeIds.has(transition.to_id),
	);
	for (const transition of validTransitions) {
		adjacency.get(transition.from_id)?.push(transition.to_id);
	}

	// DFS removing back edges (edges to a node still on the stack).
	const visiting = new Set<string>();
	const visited = new Set<string>();
	const backEdges = new Set<string>();
	const key = (from: string, to: string) => `${from}\u0000${to}`;

	const visit = (nodeId: string): void => {
		if (visited.has(nodeId)) return;
		visiting.add(nodeId);
		for (const next of adjacency.get(nodeId) ?? []) {
			if (visiting.has(next)) {
				backEdges.add(key(nodeId, next));
			} else if (!visited.has(next)) {
				visit(next);
			}
		}
		visiting.delete(nodeId);
		visited.add(nodeId);
	};

	// Visit the entry point first, then any remaining components.
	if (nodeIds.has(entryId)) visit(entryId);
	for (const node of nodes) visit(node.id);

	// Kahn's algorithm to find a topological order of the acyclic graph.
	const inDegree = new Map<string, number>();
	for (const node of nodes) inDegree.set(node.id, 0);
	for (const transition of validTransitions) {
		if (backEdges.has(key(transition.from_id, transition.to_id))) continue;
		inDegree.set(transition.to_id, (inDegree.get(transition.to_id) ?? 0) + 1);
	}

	for (const node of nodes) layers.set(node.id, 0);
	const queue = nodes
		.filter((node) => (inDegree.get(node.id) ?? 0) === 0)
		.map((node) => node.id);

	while (queue.length > 0) {
		const current = queue.shift()!;
		for (const next of adjacency.get(current) ?? []) {
			if (backEdges.has(key(current, next))) continue;
			layers.set(next, Math.max(layers.get(next) ?? 0, (layers.get(current) ?? 0) + 1));
			const remaining = (inDegree.get(next) ?? 0) - 1;
			inDegree.set(next, remaining);
			if (remaining === 0) queue.push(next);
		}
	}

	// The entry node always sits in the first column.
	if (nodeIds.has(entryId)) layers.set(entryId, 0);
	return layers;
}

// ─── Layout ──────────────────────────────────────────────────────────────────

export function computeLayout(
	template: Pick<FlowTemplate, "nodes" | "transitions" | "initial_node_id">,
): FlowLayout {
	const nodes = template.nodes ?? [];
	const transitions = template.transitions ?? [];
	if (nodes.length === 0) {
		return { nodes: [], edges: [], width: 0, height: 0 };
	}

	const layers = computeLayers(nodes, transitions, template.initial_node_id);

	// Group by layer, preserving declaration order within a layer.
	const groups = new Map<number, FlowNode[]>();
	for (const node of nodes) {
		const layer = layers.get(node.id) ?? 0;
		const bucket = groups.get(layer);
		if (bucket) bucket.push(node);
		else groups.set(layer, [node]);
	}

	const orderedLayers = [...groups.keys()].sort((a, b) => a - b);
	const maxRows = Math.max(...orderedLayers.map((l) => groups.get(l)!.length));
	const tallestLayerHeight =
		maxRows * NODE_HEIGHT + Math.max(0, maxRows - 1) * V_GAP;

	const layoutNodes: LayoutNode[] = [];
	const byId = new Map<string, LayoutNode>();
	let index = 0;

	for (const layer of orderedLayers) {
		const group = groups.get(layer)!;
		const groupHeight =
			group.length * NODE_HEIGHT + Math.max(0, group.length - 1) * V_GAP;
		const offset = (tallestLayerHeight - groupHeight) / 2;
		group.forEach((node, row) => {
			const layoutNode: LayoutNode = {
				node,
				x: PADDING + layer * (NODE_WIDTH + H_GAP),
				y: PADDING + offset + row * (NODE_HEIGHT + V_GAP),
				layer,
				index: index++,
			};
			layoutNodes.push(layoutNode);
			byId.set(node.id, layoutNode);
		});
	}

	const edges: LayoutEdge[] = [];
	for (const transition of transitions) {
		const from = byId.get(transition.from_id);
		const to = byId.get(transition.to_id);
		if (!from || !to) continue;
		const { path, labelX, labelY } = edgeGeometry(from, to);
		edges.push({ transition, from, to, path, labelX, labelY });
	}

	const width =
		PADDING * 2 +
		Math.max(...layoutNodes.map((n) => n.x)) +
		NODE_WIDTH;
	const height =
		PADDING * 2 +
		Math.max(...layoutNodes.map((n) => n.y)) +
		NODE_HEIGHT;

	return { nodes: layoutNodes, edges, width, height };
}

function edgeGeometry(
	from: LayoutNode,
	to: LayoutNode,
): { path: string; labelX: number; labelY: number } {
	// Self-loop.
	if (from.node.id === to.node.id) {
		const x = from.x + NODE_WIDTH / 2;
		const y = from.y;
		return {
			path: `M ${x - 14} ${y} C ${x - 52} ${y - 56}, ${x + 52} ${y - 56}, ${x + 14} ${y}`,
			labelX: x,
			labelY: y - 46,
		};
	}

	const startX = from.x + NODE_WIDTH;
	const startY = from.y + NODE_HEIGHT / 2;
	const endX = to.x;
	const endY = to.y + NODE_HEIGHT / 2;
	const bend = Math.max(48, Math.abs(endX - startX) * 0.5);

	return {
		path: `M ${startX} ${startY} C ${startX + bend} ${startY}, ${endX - bend} ${endY}, ${endX} ${endY}`,
		labelX: (startX + endX) / 2,
		labelY: (startY + endY) / 2 - 8,
	};
}

// ─── Status ──────────────────────────────────────────────────────────────────

/**
 * Derive a status per node from the execution state.
 *
 * `step_history` is the source of truth for completed/failed nodes; the
 * `current_node_id` overrides with running (or awaiting_input) unless the
 * flow has reached a terminal status.
 */
export function deriveNodeStatuses(
	state: FlowExecutionState | null | undefined,
	nodes?: FlowNode[],
): Record<string, FlowNodeStatus> {
	const statuses: Record<string, FlowNodeStatus> = {};
	const knownNodes = nodes ?? state?.flow_instance.nodes ?? [];
	for (const node of knownNodes) statuses[node.id] = "pending";
	if (!state) return statuses;

	for (const step of state.step_history ?? []) {
		if (!step.node_id) continue;
		if (step.status === "completed") {
			statuses[step.node_id] = "completed";
		} else if (step.status === "failed") {
			statuses[step.node_id] = "failed";
		} else if (
			(step.status === "in_progress" || step.status === "entered") &&
			statuses[step.node_id] !== "failed"
		) {
			statuses[step.node_id] = "running";
		}
	}

	const current = state.current_node_id;
	if (current) {
		switch (state.status) {
			case "awaiting_input":
				statuses[current] = "awaiting_input";
				break;
			case "completed":
			case "rejected":
			case "failed":
			case "cancelled":
				if (statuses[current] === "pending") statuses[current] = "completed";
				break;
			default:
				statuses[current] = "running";
		}
	}

	return statuses;
}

export interface NodeVisual {
	fill: string;
	opacity: number;
	stroke: string;
	strokeWidth: number;
	dashed: boolean;
	glow: boolean;
}

export function nodeVisual(
	node: FlowNode,
	status: FlowNodeStatus,
): NodeVisual {
	const fill = NODE_TYPE_COLORS[node.node_type];
	switch (status) {
		case "running":
			return {
				fill,
				opacity: 1,
				stroke: "#fbbf24",
				strokeWidth: 3,
				dashed: false,
				glow: true,
			};
		case "awaiting_input":
			return {
				fill,
				opacity: 1,
				stroke: "#f97316",
				strokeWidth: 3,
				dashed: true,
				glow: true,
			};
		case "completed":
			return {
				fill,
				opacity: 0.4,
				stroke: "#22c55e",
				strokeWidth: 1.5,
				dashed: false,
				glow: false,
			};
		case "failed":
			return {
				fill,
				opacity: 0.9,
				stroke: "#ef4444",
				strokeWidth: 2.5,
				dashed: false,
				glow: false,
			};
		default:
			return {
				fill,
				opacity: 1,
				stroke: "#1e293b",
				strokeWidth: 1,
				dashed: false,
				glow: false,
			};
	}
}

/**
 * Loop counter label, e.g. `3/50`. Returns null for non-loop nodes.
 * `max_iterations` is read from the node's loop_config.
 */
export function iterationLabel(
	node: FlowNode,
	counters: Record<string, number> | undefined,
): string | null {
	if (node.node_type !== "loop") return null;
	const count = counters?.[node.id] ?? 0;
	const max = node.loop_config?.max_iterations;
	return max != null ? `${count}/${max}` : `${count}/∞`;
}
