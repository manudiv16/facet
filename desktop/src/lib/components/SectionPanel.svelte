<script lang="ts">
	// Sections panel for the task detail page (facet#8).
	//
	// Lists the task's sections in engine order and edits them one row at a
	// time: type, content, the checklist state of checklist items, and the code
	// reference (path/lines/symbol/description). Every mutation is delegated to
	// the page's detail store through the `on*` callbacks; failures surface
	// through the `error` banner with the server message.
	import type {
		ChecklistState,
		CodeRef,
		Section,
		SectionCreateInput,
		SectionType,
		SectionUpdateInput,
	} from "$lib/types";

	export let sections: Section[] = [];
	export let loading = false;
	export let error: string | null = null;
	export let onCreate: (input: SectionCreateInput) => Promise<void> = async () => {};
	export let onUpdate: (id: string, patch: SectionUpdateInput) => Promise<void> =
		async () => {};
	export let onDelete: (id: string) => Promise<void> = async () => {};

	const SECTION_TYPES: SectionType[] = [
		"goal",
		"context",
		"current_behavior",
		"desired_behavior",
		"checklist_item",
		"testing_criterion",
		"constraint",
		"anti_pattern",
		"failure_test",
	];

	const SECTION_TYPE_LABELS: Record<SectionType, string> = {
		goal: "Goal",
		context: "Context",
		current_behavior: "Current behavior",
		desired_behavior: "Desired behavior",
		checklist_item: "Checklist item",
		testing_criterion: "Testing criterion",
		constraint: "Constraint",
		anti_pattern: "Anti-pattern",
		failure_test: "Failure test",
	};

	interface SectionDraft {
		type: SectionType;
		content: string;
		checklist: ChecklistState | null;
		path: string;
		lineStart: string;
		lineEnd: string;
		name: string;
		description: string;
	}

	function emptyDraft(): SectionDraft {
		return {
			type: "goal",
			content: "",
			checklist: null,
			path: "",
			lineStart: "",
			lineEnd: "",
			name: "",
			description: "",
		};
	}

	/** Render a code reference as `path:start-end · name — description`. */
	function codeRefLabel(ref: CodeRef): string {
		const lines =
			ref.line_start !== null && ref.line_start !== undefined
				? ref.line_end !== null &&
					ref.line_end !== undefined &&
					ref.line_end !== ref.line_start
					? `:${ref.line_start}-${ref.line_end}`
					: `:${ref.line_start}`
				: "";
		const symbol = ref.name ? ` · ${ref.name}` : "";
		const description = ref.description ? ` — ${ref.description}` : "";
		return `${ref.path}${lines}${symbol}${description}`;
	}

	// New-section form.
	let newType: SectionType = "goal";
	let newContent = "";
	let newChecklist: ChecklistState = "undone";
	let creating = false;
	let createError: string | null = null;

	// Inline editor: one row at a time.
	let editingId: string | null = null;
	let draft: SectionDraft = emptyDraft();
	let saving = false;
	let rowError: string | null = null;
	let busyId: string | null = null;

	function startEdit(section: Section) {
		editingId = section.id;
		rowError = null;
		draft = {
			type: section.section_type,
			content: section.content,
			checklist: section.checklist_state ?? null,
			path: section.code_ref?.path ?? "",
			lineStart:
				section.code_ref?.line_start !== null &&
				section.code_ref?.line_start !== undefined
					? String(section.code_ref.line_start)
					: "",
			lineEnd:
				section.code_ref?.line_end !== null &&
				section.code_ref?.line_end !== undefined
					? String(section.code_ref.line_end)
					: "",
			name: section.code_ref?.name ?? "",
			description: section.code_ref?.description ?? "",
		};
	}

	async function saveDraft(section: Section) {
		const rawLines = [draft.lineStart.trim(), draft.lineEnd.trim()];
		if (rawLines.some((raw) => raw !== "" && !/^\d+$/.test(raw))) {
			rowError = "Line numbers must be whole numbers.";
			return;
		}
		const codeRef: CodeRef | null =
			draft.path.trim() === ""
				? null
				: {
						path: draft.path.trim(),
						line_start: rawLines[0] === "" ? null : Number(rawLines[0]),
						line_end: rawLines[1] === "" ? null : Number(rawLines[1]),
						name: draft.name.trim() === "" ? null : draft.name.trim(),
						description:
							draft.description.trim() === "" ? null : draft.description.trim(),
					};

		saving = true;
		rowError = null;
		try {
			await onUpdate(section.id, {
				section_type: draft.type,
				content: draft.content,
				code_ref: codeRef,
				// Clearing keeps a section that stops being a checklist item from
				// carrying a stale done/undone state.
				checklist_state:
					draft.type === "checklist_item" ? (draft.checklist ?? "undone") : null,
			});
			editingId = null;
		} catch {
			// The panel error banner carries the server message.
		} finally {
			saving = false;
		}
	}

	async function toggleChecklist(section: Section) {
		busyId = section.id;
		try {
			await onUpdate(section.id, {
				checklist_state: section.checklist_state === "done" ? "undone" : "done",
			});
		} catch {
			// The panel error banner carries the server message.
		} finally {
			busyId = null;
		}
	}

	async function remove(section: Section) {
		busyId = section.id;
		try {
			await onDelete(section.id);
			if (editingId === section.id) editingId = null;
		} catch {
			// The panel error banner carries the server message.
		} finally {
			busyId = null;
		}
	}

	async function submitCreate() {
		if (newContent.trim() === "") {
			createError = "Content is required.";
			return;
		}
		creating = true;
		createError = null;
		try {
			await onCreate({
				section_type: newType,
				content: newContent,
				checklist_state:
					newType === "checklist_item" ? newChecklist : undefined,
			});
			newContent = "";
		} catch {
			// The panel error banner carries the server message.
		} finally {
			creating = false;
		}
	}
</script>

<section class="sections">
	<header>
		<h2>Sections</h2>
		<p class="hint">
			Structured parts of this task — goals, constraints, checklist items and
			the code they point at.
		</p>
	</header>

	{#if error}
		<div class="error-banner" role="alert">{error}</div>
	{/if}

	{#if loading}
		<p class="muted">Loading sections…</p>
	{:else if sections.length === 0}
		<p class="muted">
			{error ? "Sections could not be loaded." : "No sections."}
		</p>
	{:else}
		<ul class="section-list">
			{#each sections as section (section.id)}
				<li>
					<div class="section-head">
						<span class="section-type"
							>{SECTION_TYPE_LABELS[section.section_type] ?? section.section_type}</span
						>
						<span class="order" title="Position">#{section.order}</span>
						{#if section.checklist_state !== null}
							<button
								type="button"
								class="checklist"
								class:done={section.checklist_state === "done"}
								aria-pressed={section.checklist_state === "done"}
								disabled={busyId === section.id}
								on:click={() => toggleChecklist(section)}
							>
								{section.checklist_state === "done" ? "Done" : "Undone"}
							</button>
						{/if}
						<span class="spacer"></span>
						<button
							type="button"
							class="link"
							disabled={busyId === section.id}
							on:click={() =>
								editingId === section.id ? (editingId = null) : startEdit(section)}
						>
							{editingId === section.id ? "Cancel" : "Edit"}
						</button>
						<button
							type="button"
							class="link danger"
							disabled={busyId === section.id}
							on:click={() => remove(section)}
						>
							Delete
						</button>
					</div>

					{#if editingId === section.id}
						<div class="editor">
							{#if rowError}
								<div class="row-error" role="alert">{rowError}</div>
							{/if}
							<div class="row">
								<label>
									Type
									<select bind:value={draft.type} disabled={saving}>
										{#each SECTION_TYPES as type (type)}
											<option value={type}>{SECTION_TYPE_LABELS[type]}</option>
										{/each}
									</select>
								</label>
								{#if draft.type === "checklist_item"}
									<label>
										Checklist state
										<select bind:value={draft.checklist} disabled={saving}>
											<option value={"undone"}>Undone</option>
											<option value={"done"}>Done</option>
										</select>
									</label>
								{/if}
							</div>
							<label>
								Content
								<textarea bind:value={draft.content} rows="3" disabled={saving}
								></textarea>
							</label>
							<fieldset>
								<legend>Code reference</legend>
								<label>
									Path
									<input
										bind:value={draft.path}
										placeholder="src/lib/types.ts"
										disabled={saving}
									/>
								</label>
								<div class="row">
									<label>
										Line start
										<input
											bind:value={draft.lineStart}
											inputmode="numeric"
											placeholder="40"
											disabled={saving}
										/>
									</label>
									<label>
										Line end
										<input
											bind:value={draft.lineEnd}
											inputmode="numeric"
											placeholder="60"
											disabled={saving}
										/>
									</label>
								</div>
								<label>
									Name
									<input
										bind:value={draft.name}
										placeholder="listSections"
										disabled={saving}
									/>
								</label>
								<label>
									Description
									<input bind:value={draft.description} disabled={saving} />
								</label>
							</fieldset>
							<div class="row-actions">
								<button
									type="button"
									class="primary"
									disabled={saving}
									on:click={() => saveDraft(section)}
								>
									{saving ? "Saving…" : "Save"}
								</button>
								<button
									type="button"
									disabled={saving}
									on:click={() => (editingId = null)}
								>
									Cancel
								</button>
							</div>
						</div>
					{:else}
						<p class="content">{section.content}</p>
						{#if section.code_ref}
							<p class="code-ref">
								<code>{codeRefLabel(section.code_ref)}</code>
							</p>
						{/if}
					{/if}
				</li>
			{/each}
		</ul>
	{/if}

	<form class="add" on:submit|preventDefault={submitCreate}>
		<h3>Add a section</h3>
		{#if createError}
			<div class="row-error" role="alert">{createError}</div>
		{/if}
		<div class="row">
			<label>
				Type
				<select bind:value={newType} disabled={creating}>
					{#each SECTION_TYPES as type (type)}
						<option value={type}>{SECTION_TYPE_LABELS[type]}</option>
					{/each}
				</select>
			</label>
			{#if newType === "checklist_item"}
				<label>
					Checklist state
					<select bind:value={newChecklist} disabled={creating}>
						<option value={"undone"}>Undone</option>
						<option value={"done"}>Done</option>
					</select>
				</label>
			{/if}
		</div>
		<label>
			Content
			<textarea
				bind:value={newContent}
				rows="3"
				placeholder="What the engine should know about this task"
				disabled={creating}
			></textarea>
		</label>
		<div class="row-actions">
			<button type="submit" class="primary" disabled={creating}>
				{creating ? "Adding…" : "Add section"}
			</button>
		</div>
	</form>
</section>

<style>
	.sections {
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 12px;
		padding: 1rem 1.15rem;
	}

	h2 {
		margin: 0;
		font-size: 1rem;
	}

	h3 {
		margin: 0;
		font-size: 0.9rem;
	}

	.hint {
		margin: 0.2rem 0 0;
		color: var(--text-muted);
		font-size: 0.82rem;
	}

	.error-banner,
	.row-error {
		padding: 0.55rem 0.75rem;
		border-radius: 8px;
		border: 1px solid rgba(239, 68, 68, 0.4);
		background: rgba(239, 68, 68, 0.08);
		color: #ef4444;
		font-size: 0.85rem;
	}

	.section-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}

	.section-list > li {
		border: 1px solid var(--border);
		border-radius: 10px;
		padding: 0.6rem 0.75rem;
		background: var(--surface-2);
	}

	.section-head {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.section-type {
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--accent);
	}

	.order {
		font-size: 0.72rem;
		color: var(--text-muted);
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
	}

	.spacer {
		flex: 1;
	}

	.checklist {
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text-muted);
		border-radius: 999px;
		padding: 0.1rem 0.6rem;
		font: inherit;
		font-size: 0.72rem;
		cursor: pointer;
	}

	.checklist.done {
		border-color: var(--accent);
		color: var(--accent);
		font-weight: 600;
	}

	.checklist:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.link {
		border: none;
		background: none;
		color: var(--accent);
		font: inherit;
		font-size: 0.8rem;
		cursor: pointer;
		padding: 0.1rem 0.25rem;
	}

	.link.danger {
		color: #ef4444;
	}

	.link:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.content {
		margin: 0.4rem 0 0;
		white-space: pre-wrap;
		font-size: 0.88rem;
	}

	.code-ref {
		margin: 0.35rem 0 0;
	}

	code {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 0.78rem;
		color: var(--text-muted);
	}

	.editor {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		margin-top: 0.6rem;
	}

	.row {
		display: flex;
		gap: 0.75rem;
		flex-wrap: wrap;
	}

	label {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 0.78rem;
		color: var(--text-muted);
		flex: 1;
		min-width: 8rem;
	}

	fieldset {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		border: 1px dashed var(--border);
		border-radius: 8px;
		padding: 0.6rem 0.7rem;
	}

	legend {
		font-size: 0.75rem;
		color: var(--text-muted);
		padding: 0 0.3rem;
	}

	input,
	select,
	textarea {
		background: var(--surface-1);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 0.4rem 0.55rem;
		color: var(--text);
		font: inherit;
		font-size: 0.85rem;
		width: 100%;
		box-sizing: border-box;
	}

	textarea {
		resize: vertical;
	}

	.row-actions {
		display: flex;
		gap: 0.5rem;
	}

	.row-actions button {
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text);
		border-radius: 8px;
		padding: 0.4rem 0.7rem;
		font: inherit;
		font-size: 0.82rem;
		cursor: pointer;
	}

	.row-actions button:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.primary {
		background: var(--accent);
		color: white;
		border-color: transparent;
		font-weight: 600;
	}

	.add {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		border-top: 1px solid var(--border);
		padding-top: 0.85rem;
	}

	.muted {
		margin: 0;
		color: var(--text-muted);
		font-size: 0.85rem;
	}
</style>
