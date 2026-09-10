<script lang="ts">
	import {
		computeLayout,
		iterationLabel,
		NODE_HEIGHT,
		NODE_TYPE_COLORS,
		NODE_TYPE_ICONS,
		NODE_TYPE_LABELS,
		NODE_WIDTH,
		nodeVisual,
	} from '$lib/flow-layout';
	import type { FlowNodeStatus, FlowNodeType, FlowTemplate } from '$lib/types';

	/** Template graph to render. */
	export let template: FlowTemplate;
	/** Node id → execution status. Completed nodes are dimmed. */
	export let nodeStatuses: Record<string, FlowNodeStatus> = {};
	/** Currently executing node (highlighted). */
	export let currentNodeId: string | null = null;
	/** Loop node id → iteration count. */
	export let iterationCounters: Record<string, number> = {};
	/** Currently selected node (clicked). */
	export let selectedNodeId: string | null = null;
	/** Optional click handler for node selection. */
	export let onSelectNode: ((nodeId: string) => void) | null = null;

	$: layout = computeLayout(template);

	const TYPE_ORDER: FlowNodeType[] = [
		'step',
		'sequence',
		'branch',
		'loop',
		'parallel',
		'human_input',
	];

	/** Status of a node, defaulting to pending. */
	function statusOf(nodeId: string): FlowNodeStatus {
		return nodeStatuses[nodeId] ?? 'pending';
	}

	function isCurrent(nodeId: string): boolean {
		return currentNodeId === nodeId || statusOf(nodeId) === 'running';
	}

	/** Greedy word-wrap into at most two SVG text lines. */
	function wrapLabel(text: string, maxChars = 22): string[] {
		const words = text.split(/\s+/).filter(Boolean);
		if (words.length === 0) return [''];
		const lines: string[] = [];
		let line = '';
		for (const word of words) {
			const candidate = line ? `${line} ${word}` : word;
			if (candidate.length <= maxChars) {
				line = candidate;
			} else {
				if (line) lines.push(line);
				line = word;
				if (lines.length === 2) break;
			}
		}
		if (lines.length < 2 && line) lines.push(line);
		if (lines.length === 2 && line && lines[1] !== line) {
			lines[1] = `${line.slice(0, maxChars - 1)}…`;
		}
		return lines;
	}

	function handleActivate(nodeId: string) {
		if (onSelectNode) onSelectNode(nodeId);
	}

	function handleKeydown(event: KeyboardEvent, nodeId: string) {
		if (event.key === 'Enter' || event.key === ' ') {
			event.preventDefault();
			handleActivate(nodeId);
		}
	}
</script>

<div class="flow-graph">
	<div class="legend" aria-label="Node type legend">
		{#each TYPE_ORDER as type (type)}
			<span class="legend-item">
				<span class="swatch" style={`background:${NODE_TYPE_COLORS[type]}`}></span>
				{NODE_TYPE_LABELS[type]}
			</span>
		{/each}
		<span class="legend-item legend-sep">
			<span class="swatch swatch-current"></span>
			current
		</span>
		<span class="legend-item">
			<span class="swatch swatch-done"></span>
			completed
		</span>
	</div>

	{#if layout.nodes.length === 0}
		<p class="empty">This template has no nodes to render.</p>
	{:else}
		<svg
			width={layout.width}
			height={layout.height}
			viewBox={`0 0 ${layout.width} ${layout.height}`}
			role="img"
			aria-label={`${template.name} flow graph with ${layout.nodes.length} nodes`}
		>
			<defs>
				<marker
					id="flow-arrow"
					markerWidth="10"
					markerHeight="10"
					refX="8"
					refY="3"
					orient="auto"
					markerUnits="strokeWidth"
				>
					<path d="M 0 0 L 8 3 L 0 6 z" fill="#64748b" />
				</marker>
				<filter id="flow-glow" x="-40%" y="-40%" width="180%" height="180%">
					<feGaussianBlur stdDeviation="4" result="blur" />
					<feMerge>
						<feMergeNode in="blur" />
						<feMergeNode in="SourceGraphic" />
					</feMerge>
				</filter>
			</defs>

			<!-- Edges -->
			<g class="edges">
				{#each layout.edges as edge (edge.transition.id || `${edge.from.node.id}->${edge.to.node.id}`)}
					<path
						class="edge-path"
						d={edge.path}
						fill="none"
						marker-end="url(#flow-arrow)"
					/>
					{#if edge.transition.label || edge.transition.condition}
						<text class="edge-label" x={edge.labelX} y={edge.labelY} text-anchor="middle">
							{edge.transition.label ?? edge.transition.condition}
						</text>
					{/if}
				{/each}
			</g>

			<!-- Nodes -->
			<g class="nodes">
				{#each layout.nodes as item (item.node.id)}
					{@const status = statusOf(item.node.id)}
					{@const visual = nodeVisual(item.node, status)}
					{@const loop = iterationLabel(item.node, iterationCounters)}
					{@const failed = status === 'failed'}
					<g
						class="node"
						class:current={isCurrent(item.node.id) && !failed}
						class:completed={status === 'completed'}
						class:awaiting={status === 'awaiting_input'}
						class:selected={selectedNodeId === item.node.id}
						transform={`translate(${item.x}, ${item.y})`}
						role="button"
						tabindex={onSelectNode ? 0 : -1}
						aria-label={`${item.node.name} (${NODE_TYPE_LABELS[item.node.node_type]}, ${status})`}
						on:click={() => handleActivate(item.node.id)}
						on:keydown={(event) => handleKeydown(event, item.node.id)}
					>
						<title>
							{item.node.name} — {NODE_TYPE_LABELS[item.node.node_type]} ({status})
							{item.node.goal ? `: ${item.node.goal}` : ''}
						</title>
						<rect
							width={NODE_WIDTH}
							height={NODE_HEIGHT}
							rx="10"
							fill={visual.fill}
							fill-opacity={visual.opacity}
							stroke={visual.stroke}
							stroke-width={visual.strokeWidth}
							stroke-dasharray={visual.dashed ? '6 4' : undefined}
							filter={visual.glow ? 'url(#flow-glow)' : undefined}
						/>
						<text class="badge" x="12" y="22">
							{NODE_TYPE_ICONS[item.node.node_type]}
							{NODE_TYPE_LABELS[item.node.node_type]}
						</text>
						{#if loop}
							<text class="loop-counter" x={NODE_WIDTH - 12} y="22" text-anchor="end">
								{loop}
							</text>
						{/if}
						{#if status === 'completed'}
							<text class="status-mark" x={NODE_WIDTH - 12} y={NODE_HEIGHT - 12} text-anchor="end">
								✓
							</text>
						{:else if status === 'failed'}
							<text class="status-mark failed-mark" x={NODE_WIDTH - 12} y={NODE_HEIGHT - 12} text-anchor="end">
								✗
							</text>
						{:else if status === 'awaiting_input'}
							<text class="status-mark awaiting-mark" x={NODE_WIDTH - 12} y={NODE_HEIGHT - 12} text-anchor="end">
								awaiting input
							</text>
						{/if}
						<text class="node-name" x={NODE_WIDTH / 2} text-anchor="middle">
							{#each wrapLabel(item.node.name) as line, index (index)}
								<tspan
									x={NODE_WIDTH / 2}
									dy={index === 0 ? (wrapLabel(item.node.name).length > 1 ? NODE_HEIGHT / 2 - 6 : NODE_HEIGHT / 2 + 5) : 17}
								>
									{line}
								</tspan>
							{/each}
						</text>
					</g>
				{/each}
			</g>
		</svg>
	{/if}
</div>

<style>
	.flow-graph {
		background: var(--surface-1, #0f172a);
		border: 1px solid var(--border, #1e293b);
		border-radius: 10px;
		overflow: auto;
		padding: 0.5rem;
	}

	svg {
		display: block;
	}

	.legend {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem 1.25rem;
		padding: 0.5rem 0.75rem 0.75rem;
		font-size: 0.75rem;
		color: var(--text-muted, #94a3b8);
	}

	.legend-item {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}

	.legend-sep {
		margin-left: 0.5rem;
		padding-left: 1rem;
		border-left: 1px solid var(--border, #1e293b);
	}

	.swatch {
		width: 12px;
		height: 12px;
		border-radius: 3px;
		display: inline-block;
	}

	.swatch-current {
		background: #fbbf24;
	}

	.swatch-done {
		background: #22c55e;
		opacity: 0.5;
	}

	.edge-path {
		stroke: #475569;
		stroke-width: 2;
	}

	.edge-label {
		font-size: 11px;
		fill: var(--text-muted, #cbd5e1);
		paint-order: stroke;
		stroke: var(--surface-1, #0f172a);
		stroke-width: 4px;
		stroke-linejoin: round;
	}

	.node {
		cursor: pointer;
		outline: none;
	}

	.node:focus-visible rect {
		stroke: #e2e8f0;
		stroke-width: 3;
	}

	.node.selected rect {
		stroke: #e2e8f0;
		stroke-width: 3;
	}

	.node.completed {
		transition: opacity 0.2s ease;
	}

	.node:not(.completed):hover rect {
		filter: brightness(1.12);
	}

	.badge {
		font-size: 10px;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		fill: rgba(255, 255, 255, 0.78);
		pointer-events: none;
	}

	.loop-counter {
		font-size: 11px;
		font-weight: 700;
		fill: rgba(255, 255, 255, 0.92);
		pointer-events: none;
	}

	.node-name {
		font-size: 13px;
		font-weight: 600;
		fill: #f8fafc;
		pointer-events: none;
	}

	.status-mark {
		font-size: 14px;
		font-weight: 700;
		fill: #bbf7d0;
		pointer-events: none;
	}

	.failed-mark {
		fill: #fecaca;
	}

	.awaiting-mark {
		font-size: 10px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		fill: #fed7aa;
	}

	.empty {
		padding: 2rem;
		text-align: center;
		color: var(--text-muted, #64748b);
	}
</style>
