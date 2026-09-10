<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { useSessionLog } from '$lib/stores';
  import { formatTime } from '$lib/format';

  export let executionId: string;
  export let status: string = 'pending';

  const MAX_TOOL_OUTPUT = 500;

  // A stable per-instance store; the parent keys the component by executionId
  // so switching executions re-mounts it.
  const logStore = useSessionLog(executionId);
  const { events, loading, loadingOlder, error, hasMore, polling } = logStore;

  onMount(() => {
    logStore.init(status);
  });

  onDestroy(() => {
    logStore.destroy();
  });

  // Whenever the execution reaches a terminal status, stop refreshing.
  $: logStore.updateStatus(status);

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
      {#if $polling}
        <span class="live-dot" title="Refreshing every 3s"></span>
        <span class="live-label">live</span>
      {/if}
      <span class="event-count">
        {$events.length} event{$events.length === 1 ? '' : 's'}
      </span>
    </div>
  </div>

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
