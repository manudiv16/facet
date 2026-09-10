<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { useExecutionHistory } from "$lib/stores";
  import {
    formatCost,
    formatDuration,
    formatNumber,
    formatSpan,
    formatTimestamp,
  } from "$lib/format";
  import type { Execution, ExecutionStatus } from "$lib/types";
  import SessionLog from "./SessionLog.svelte";

  export let taskId: string;

  const store = useExecutionHistory(taskId);
  const { executions, aggregate, loading, loadingOlder, hasMore, polling, error } =
    store;

  let selectedId: string | null = null;

  onMount(() => {
    void store.load();
  });

  onDestroy(() => store.destroy());

  // Keep a valid selection as rows stream in. Default to the newest row.
  $: if ($executions.length > 0 && !$executions.some((e) => e.id === selectedId)) {
    selectedId = $executions[0].id;
  }

  $: selected = $executions.find((e) => e.id === selectedId) ?? null;

  function statusClass(status: ExecutionStatus): string {
    switch (status) {
      case "completed":
        return "ok";
      case "failed":
      case "rejected":
        return "bad";
      case "in_progress":
      case "running":
      case "entered":
      case "awaiting_input":
        return "active";
      case "cancelled":
        return "muted";
      default:
        return "pending";
    }
  }

  function durationLabel(execution: Execution): string {
    if (execution.duration_ms > 0) return formatDuration(execution.duration_ms);
    return formatSpan(execution.started_at, execution.completed_at);
  }
</script>

<section class="history">
  <header class="history-header">
    <div>
      <h2>Execution history</h2>
      <p class="muted">
        Task <code>{taskId}</code> — one row per step, newest first.
      </p>
    </div>
    <div class="history-meta">
      {#if $polling}
        <span class="live-dot" title="Refreshing every 3s"></span>
        <span class="live-label">live</span>
      {/if}
      {#if $error}
        <span class="error-inline">{$error}</span>
      {/if}
    </div>
  </header>

  {#if $loading}
    <div class="state">Loading executions…</div>
  {:else if $executions.length === 0}
    <div class="state">
      {#if $error}
        Could not load executions: {$error}
      {:else}
        No executions recorded for this task yet.
      {/if}
    </div>
  {:else}
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th scope="col">Node</th>
            <th scope="col">Status</th>
            <th scope="col">Model</th>
            <th scope="col" class="num">Input</th>
            <th scope="col" class="num">Output</th>
            <th scope="col" class="num">Cost</th>
            <th scope="col">Duration</th>
            <th scope="col">Started</th>
            <th scope="col">Completed</th>
          </tr>
        </thead>
        <tbody>
          {#each $executions as execution (execution.id)}
            <tr class:selected={execution.id === selectedId}>
              <td class="node">
                <button
                  type="button"
                  class="node-link"
                  aria-pressed={execution.id === selectedId}
                  on:click={() => (selectedId = execution.id)}
                >
                  {execution.node_id || "—"}
                </button>
              </td>
              <td>
                <span class="badge badge-{statusClass(execution.status)}">
                  {execution.status.replace("_", " ")}
                </span>
              </td>
              <td class="model">{execution.model || "—"}</td>
              <td class="num">{formatNumber(execution.input_tokens)}</td>
              <td class="num">{formatNumber(execution.output_tokens)}</td>
              <td class="num cost">{formatCost(execution.cost)}</td>
              <td>{durationLabel(execution)}</td>
              <td class="time">{formatTimestamp(execution.started_at)}</td>
              <td class="time">{formatTimestamp(execution.completed_at)}</td>
            </tr>
          {/each}
        </tbody>
        <tfoot>
          <tr>
            <th scope="row" colspan="3">Totals</th>
            <td class="num">{$aggregate.total_input_tokens.toLocaleString()}</td>
            <td class="num">{$aggregate.total_output_tokens.toLocaleString()}</td>
            <td class="num cost">{formatCost($aggregate.total_cost)}</td>
            <td colspan="3"></td>
          </tr>
        </tfoot>
      </table>
    </div>

    {#if $hasMore}
      <div class="load-older">
        <button on:click={() => store.loadOlder()} disabled={$loadingOlder}>
          {$loadingOlder ? "Loading…" : "Load older executions"}
        </button>
      </div>
    {/if}
  {/if}

  {#if selected}
    <div class="log-pane">
      {#key selected.id}
        <SessionLog executionId={selected.id} status={selected.status} />
      {/key}
    </div>
  {/if}
</section>

<style>
  .history {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .history-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
  }

  .history-header h2 {
    margin: 0 0 0.25rem;
    font-size: 1.15rem;
  }

  .muted {
    margin: 0;
    color: var(--text-muted);
    font-size: 0.9rem;
  }

  .history-meta {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.8rem;
    color: var(--text-muted);
  }

  .live-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #22c55e;
    box-shadow: 0 0 6px #22c55e;
  }

  .error-inline {
    color: #ef4444;
  }

  .state {
    padding: 2rem;
    text-align: center;
    color: var(--text-muted);
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: 12px;
  }

  .table-wrap {
    overflow-x: auto;
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: 12px;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.875rem;
  }

  th,
  td {
    padding: 0.55rem 0.75rem;
    text-align: left;
    border-bottom: 1px solid var(--border);
    white-space: nowrap;
  }

  thead th {
    color: var(--text-muted);
    font-weight: 600;
    background: var(--surface-2);
    position: sticky;
    top: 0;
  }

  tbody tr:hover {
    background: var(--surface-2);
  }

  tbody tr.selected {
    background: color-mix(in srgb, var(--accent) 12%, transparent);
  }

  tfoot th,
  tfoot td {
    font-weight: 700;
    background: var(--surface-2);
    border-bottom: none;
  }

  .num {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }

  .cost {
    font-variant-numeric: tabular-nums;
  }

  .time {
    color: var(--text-muted);
    font-size: 0.8rem;
  }

  .model {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.8rem;
  }

  .node-link {
    padding: 0;
    border: none;
    background: none;
    color: var(--accent);
    font: inherit;
    font-weight: 600;
    cursor: pointer;
    text-align: left;
  }

  .node-link:hover {
    text-decoration: underline;
  }

  .badge {
    display: inline-block;
    padding: 0.12rem 0.5rem;
    border-radius: 999px;
    font-size: 0.72rem;
    font-weight: 600;
    text-transform: capitalize;
  }

  .badge-ok {
    background: rgba(34, 197, 94, 0.15);
    color: #16a34a;
  }

  .badge-bad {
    background: rgba(239, 68, 68, 0.15);
    color: #ef4444;
  }

  .badge-active {
    background: rgba(59, 130, 246, 0.15);
    color: var(--accent);
  }

  .badge-muted,
  .badge-pending {
    background: var(--surface-3);
    color: var(--text-muted);
  }

  .load-older {
    text-align: center;
  }

  .load-older button {
    padding: 0.5rem 1rem;
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: 8px;
    color: var(--text);
    cursor: pointer;
    font: inherit;
  }

  .load-older button:hover:not(:disabled) {
    background: var(--surface-2);
  }

  .load-older button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .log-pane {
    margin-top: 0.5rem;
  }
</style>
