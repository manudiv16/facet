<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { useSessionLog } from '$lib/stores';
  import { formatTime } from '$lib/format';
  import type { StepStatusFrame } from '$lib/execution-stream';

  export let executionId: string;
  export let status: string = 'pending';
  // The parent table listens so the row's status follows the stream too.
  export let onStepStatus: ((frame: StepStatusFrame) => void) | undefined = undefined;

  const MAX_TOOL_OUTPUT = 500;

  // A stable per-instance store; the parent keys the component by executionId
  // so switching executions re-mounts it. The REST backlog loads first; the
  // engine's event stream appends from there.
  const logStore = useSessionLog(executionId, {
    onStepStatus: (frame) => onStepStatus?.(frame),
  });
  const { events, loading, loadingOlder, error, hasMore, live, streamState, gap } = logStore;

  onMount(() => {
    void logStore.init(status);
  });

  onDestroy(() => {
    logStore.destroy();
  });

  // Whenever the execution reaches a terminal status, close the stream: the
  // REST backlog is the whole story from then on.
  $: logStore.updateStatus(status);

  function gapLabel(reason: string): string {
    switch (reason) {
      case 'sequence_gap':
        return 'missed events — reloaded from the API';
      case 'restart':
        return 'engine restarted — reloaded from the API';
      default:
        return 'reconnected — reloaded from the API';
    }
  }

  function truncateOutput(output: string): { text: string; truncated: boolean } {
    if (output.length <= MAX_TOOL_OUTPUT) return { text: output, truncated: false };
    return { text: output.slice(0, MAX_TOOL_OUTPUT), truncated: true };
  }

  function formatJson(obj: unknown): string {
    if (obj === null || obj === undefined) return '—';
    if (typeof obj === 'string') return obj;
    try {
      return JSON.stringify(obj, null, 2);
    } catch {
      return String(obj);
    }
  }
</script>

<div class="session-log">
  <div class="log-toolbar">
    <h3>Session log</h3>
    <div class="log-meta">
      {#if $live}
        <span class="live-dot" title="Streaming engine events"></span>
        <span class="live-label">live</span>
      {:else if $streamState === 'connecting' || $streamState === 'reconnecting'}
        <span class="live-dot reconnecting" title="Reconnecting to the event stream"></span>
        <span class="live-label">reconnecting</span>
      {/if}
      <span class="event-count">
        {$events.length} event{$events.length === 1 ? '' : 's'}
      </span>
      <button
        type="button"
        class="refresh"
        on:click={() => logStore.refresh()}
        disabled={$loading}
      >
        Refresh
      </button>
    </div>
  </div>

  {#if $gap}
    <p class="gap-note" role="status">{gapLabel($gap.reason)}</p>
  {/if}

  {#if $loading}
    <div class="loading">Loading session log…</div>
  {:else if $error}
    <div class="error">Error: {$error}</div>
  {:else}
    {#if $hasMore}
      <div class="load-older">
        <button on:click={() => logStore.loadOlder()} disabled={$loadingOlder}>
          {$loadingOlder ? 'Loading…' : 'Load older events'}
        </button>
      </div>
    {/if}

    {#if $events.length === 0}
      <div class="empty">No events recorded</div>
    {:else}
      <div class="events">
        {#each $events as event (event.id)}
          <div class="event event-{event.kind}">
            <div class="event-header">
              <span class="event-kind">{event.kind.replace('_', ' ')}</span>
              <span class="event-time">{formatTime(event.timestamp)}</span>
            </div>
            <div class="event-content">
              {#if event.kind === 'text'}
                <div class="text-content">{event.data.content}</div>
              {:else if event.kind === 'tool_use'}
                <div class="tool-use">
                  <div class="tool-name">🔧 {event.data.tool_name}</div>
                  <pre class="tool-input">{formatJson(event.data.tool_input)}</pre>
                </div>
              {:else if event.kind === 'tool_result'}
                {@const shown = truncateOutput(event.data.output)}
                <div class="tool-result">
                  <div class="tool-name">✓ {event.data.tool_name}</div>
                  <pre class="tool-output">{shown.text}</pre>
                  {#if shown.truncated || event.data.truncated}
                    <div class="truncated-notice">(output truncated)</div>
                  {/if}
                </div>
              {:else if event.kind === 'usage'}
                <div class="usage">
                  <span class="token-count">Input: {event.data.input_tokens.toLocaleString()}</span>
                  <span class="token-count">Output: {event.data.output_tokens.toLocaleString()}</span>
                </div>
              {:else if event.kind === 'outcome'}
                <div class="outcome" class:success={event.data.success} class:failure={!event.data.success}>
                  {#if event.data.success}
                    ✓ Completed successfully
                  {:else}
                    ✗ Failed
                  {/if}
                  {#if event.data.result}
                    <div class="outcome-result">{event.data.result}</div>
                  {/if}
                </div>
              {:else if event.kind === 'error'}
                <div class="error-event">
                  <div class="error-type">{event.data.error_type}</div>
                  <div class="error-message">{event.data.message}</div>
                  {#if event.data.stack}
                    <pre class="error-stack">{event.data.stack}</pre>
                  {/if}
                </div>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</div>

<style>
  .session-log {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1rem;
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: 12px;
  }

  .log-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .log-toolbar h3 {
    margin: 0;
    font-size: 1rem;
  }

  .log-meta {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--text-muted);
    font-size: 0.75rem;
  }

  .live-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--success, #22c55e);
    box-shadow: 0 0 6px var(--success, #22c55e);
  }

  .live-dot.reconnecting {
    background: var(--warning, #f59e0b);
    box-shadow: 0 0 6px var(--warning, #f59e0b);
  }

  .refresh {
    padding: 0.15rem 0.5rem;
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    color: var(--text);
    font: inherit;
    font-size: 0.75rem;
    cursor: pointer;
  }

  .refresh:hover:not(:disabled) {
    background: var(--surface-3);
  }

  .refresh:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .gap-note {
    margin: 0;
    padding: 0.4rem 0.6rem;
    border-radius: 6px;
    background: rgba(245, 158, 11, 0.12);
    color: var(--warning, #f59e0b);
    font-size: 0.75rem;
  }

  .loading,
  .empty,
  .error {
    padding: 2rem;
    text-align: center;
    color: var(--text-muted);
  }

  .error {
    color: var(--error, #ef4444);
  }

  .load-older {
    text-align: center;
    padding: 0.25rem;
  }

  .load-older button {
    padding: 0.5rem 1rem;
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: 8px;
    color: var(--text);
    cursor: pointer;
    font: inherit;
  }

  .load-older button:hover:not(:disabled) {
    background: var(--surface-3);
  }

  .load-older button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .events {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .event {
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
  }

  .event-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0.75rem;
    background: var(--surface-3);
    border-bottom: 1px solid var(--border);
    font-size: 0.875rem;
  }

  .event-kind {
    font-weight: 600;
    text-transform: uppercase;
    font-size: 0.75rem;
    letter-spacing: 0.5px;
  }

  .event-time {
    color: var(--text-muted);
    font-size: 0.75rem;
  }

  .event-content {
    padding: 0.75rem;
  }

  .text-content {
    white-space: pre-wrap;
    word-break: break-word;
  }

  .tool-use,
  .tool-result {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .tool-name {
    font-weight: 600;
    color: var(--accent);
  }

  .tool-input,
  .tool-output,
  .error-stack {
    background: var(--bg, #0a0a0a);
    padding: 0.75rem;
    border-radius: 6px;
    overflow-x: auto;
    font-size: 0.8125rem;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .truncated-notice {
    color: var(--text-muted);
    font-style: italic;
    font-size: 0.75rem;
  }

  .usage {
    display: flex;
    gap: 1rem;
    font-size: 0.875rem;
  }

  .token-count {
    padding: 0.25rem 0.5rem;
    background: var(--surface-3);
    border-radius: 4px;
  }

  .outcome {
    padding: 0.5rem;
    border-radius: 6px;
    font-weight: 600;
  }

  .outcome.success {
    background: rgba(34, 197, 94, 0.12);
    color: var(--success, #22c55e);
  }

  .outcome.failure {
    background: rgba(239, 68, 68, 0.12);
    color: var(--error, #ef4444);
  }

  .outcome-result {
    margin-top: 0.5rem;
    font-weight: 400;
    font-size: 0.875rem;
  }

  .error-event {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .error-type {
    font-weight: 600;
    color: var(--error, #ef4444);
  }

  .error-message {
    color: var(--text);
  }

  /* Event type colours */
  .event-tool_use .event-kind {
    color: var(--accent);
  }

  .event-tool_result .event-kind {
    color: var(--success, #22c55e);
  }

  .event-usage .event-kind {
    color: var(--warning, #f59e0b);
  }

  .event-outcome .event-kind {
    color: var(--info, #06b6d4);
  }

  .event-error .event-kind {
    color: var(--error, #ef4444);
  }
</style>
