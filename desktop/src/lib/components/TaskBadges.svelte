<script lang="ts">
	import {
		LEVEL_LABELS,
		PRIORITY_LABELS,
		STATUS_LABELS,
	} from '$lib/tasks-utils';
	import type { TaskLevel, TaskPriority, TaskStatus } from '$lib/types';

	export let level: TaskLevel | undefined = undefined;
	export let priority: TaskPriority | undefined = undefined;
	export let status: TaskStatus | undefined = undefined;
	export let compact = false;
</script>

<span class="badges" class:compact>
	{#if level}
		<span class="badge level level-{level}">{LEVEL_LABELS[level]}</span>
	{/if}
	{#if status}
		<span class="badge status status-{status}">{STATUS_LABELS[status]}</span>
	{/if}
	{#if priority}
		<span class="badge priority priority-{priority}">{PRIORITY_LABELS[priority]}</span>
	{/if}
</span>

<style>
	.badges {
		display: inline-flex;
		flex-wrap: wrap;
		gap: 0.25rem;
		align-items: center;
	}

	.badge {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 600;
		line-height: 1.4;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		border: 1px solid transparent;
		white-space: nowrap;
	}

	.compact .badge {
		font-size: 0.65rem;
		padding: 0.05rem 0.35rem;
	}

	/* Level */
	.level-epic {
		background: rgba(139, 92, 246, 0.15);
		color: #a78bfa;
		border-color: rgba(139, 92, 246, 0.4);
	}
	.level-ticket {
		background: rgba(59, 130, 246, 0.15);
		color: #60a5fa;
		border-color: rgba(59, 130, 246, 0.4);
	}
	.level-task {
		background: rgba(148, 163, 184, 0.15);
		color: #94a3b8;
		border-color: rgba(148, 163, 184, 0.4);
	}

	/* Status */
	.status-todo {
		background: rgba(148, 163, 184, 0.15);
		color: #cbd5e1;
		border-color: rgba(148, 163, 184, 0.4);
	}
	.status-in_progress {
		background: rgba(59, 130, 246, 0.15);
		color: #60a5fa;
		border-color: rgba(59, 130, 246, 0.4);
	}
	.status-blocked {
		background: rgba(239, 68, 68, 0.15);
		color: #f87171;
		border-color: rgba(239, 68, 68, 0.4);
	}
	.status-done {
		background: rgba(34, 197, 94, 0.15);
		color: #4ade80;
		border-color: rgba(34, 197, 94, 0.4);
	}
	.status-cancelled,
	.status-archived {
		background: rgba(100, 116, 139, 0.15);
		color: #94a3b8;
		border-color: rgba(100, 116, 139, 0.4);
	}

	/* Priority */
	.priority-low {
		background: rgba(148, 163, 184, 0.15);
		color: #94a3b8;
		border-color: rgba(148, 163, 184, 0.4);
	}
	.priority-medium {
		background: rgba(6, 182, 212, 0.15);
		color: #22d3ee;
		border-color: rgba(6, 182, 212, 0.4);
	}
	.priority-high {
		background: rgba(245, 158, 11, 0.15);
		color: #fbbf24;
		border-color: rgba(245, 158, 11, 0.4);
	}
	.priority-critical {
		background: rgba(239, 68, 68, 0.2);
		color: #f87171;
		border-color: rgba(239, 68, 68, 0.5);
	}
</style>
