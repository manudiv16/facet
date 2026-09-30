// Acceptance tests for the sections client (`$lib/sections-api`).
//
// The transport is mocked so the assertions can fail on a plausible
// regression: a wrong verb/path (the five section routes), a body that sends
// keys the engine must not receive (an absent `order`/`code_ref` must stay
// absent so the engine assigns the next position), and a payload the panel
// would render out of order.
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./api", () => ({
	api: {
		get: vi.fn(),
		post: vi.fn(),
		patch: vi.fn(),
		delete: vi.fn(),
	},
}));

import { api } from "./api";
import {
	createSection,
	deleteSection,
	getSection,
	listSections,
	normalizeSection,
	sortSections,
	updateSection,
} from "./sections-api";
import type { Section } from "./types";

const getMock = api.get as ReturnType<typeof vi.fn>;
const postMock = api.post as ReturnType<typeof vi.fn>;
const patchMock = api.patch as ReturnType<typeof vi.fn>;
const deleteMock = api.delete as ReturnType<typeof vi.fn>;

beforeEach(() => {
	getMock.mockReset();
	postMock.mockReset();
	patchMock.mockReset();
	deleteMock.mockReset();
});

/** A Crystalline section wire row. */
function sectionRaw(overrides: Record<string, unknown> = {}): Record<string, unknown> {
	return {
		id: "section-1",
		task_id: "task-1",
		section_type: "goal",
		content: "Ship the sections panel",
		code_ref: null,
		order: 0,
		checklist_state: null,
		...overrides,
	};
}

describe("normalizeSection", () => {
	it("keeps a full code reference and the checklist state", () => {
		const section = normalizeSection({
			...sectionRaw({
				section_type: "checklist_item",
				checklist_state: "done",
				code_ref: {
					path: "src/lib/sections-api.ts",
					line_start: 40,
					line_end: 60,
					name: "listSections",
					description: "task sections",
				},
			}),
			id: "section-7",
		} as Partial<Section> & { id: string });

		expect(section.section_type).toBe("checklist_item");
		expect(section.checklist_state).toBe("done");
		expect(section.code_ref).toEqual({
			path: "src/lib/sections-api.ts",
			line_start: 40,
			line_end: 60,
			name: "listSections",
			description: "task sections",
		});
	});

	it("treats an absent/empty code reference and unknown state as none", () => {
		const section = normalizeSection({
			...sectionRaw({
				code_ref: { path: "", line_start: 3 },
				checklist_state: "maybe",
				order: undefined,
			}),
			id: "section-8",
		} as Partial<Section> & { id: string });

		expect(section.code_ref).toBeNull();
		expect(section.checklist_state).toBeNull();
		expect(section.order).toBe(0);
	});

	it("fills the nullable code-ref fields when the engine omits them", () => {
		const section = normalizeSection({
			...sectionRaw({ code_ref: { path: "README.md" } }),
			id: "section-9",
		} as Partial<Section> & { id: string });

		expect(section.code_ref).toEqual({
			path: "README.md",
			line_start: null,
			line_end: null,
			name: null,
			description: null,
		});
	});
});

describe("sortSections", () => {
	it("orders by `order` and keeps the incoming sequence for ties", () => {
		const rows = [
			{ id: "b", order: 2 },
			{ id: "c", order: 0 },
			{ id: "a", order: 0 },
		] as Section[];
		expect(sortSections(rows).map((section) => section.id)).toEqual([
			"c",
			"a",
			"b",
		]);
	});
});

describe("listSections", () => {
	it("GETs the task's sections and returns them in `order`", async () => {
		getMock.mockResolvedValue([
			sectionRaw({ id: "s-2", order: 1, section_type: "constraint" }),
			sectionRaw({ id: "s-1", order: 0 }),
		]);

		const sections = await listSections("task 1/x");

		expect(getMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task%201%2Fx/sections",
		);
		expect(sections.map((section) => section.id)).toEqual(["s-1", "s-2"]);
		expect(sections[1].section_type).toBe("constraint");
	});

	it("returns an empty list when the engine answers with a non-array", async () => {
		getMock.mockResolvedValue({ error: "boom" });
		await expect(listSections("task-1")).resolves.toEqual([]);
	});
});

describe("getSection", () => {
	it("GETs one section by id", async () => {
		getMock.mockResolvedValue(sectionRaw({ id: "s-9" }));
		const section = await getSection("s-9");
		expect(getMock).toHaveBeenCalledWith("/api/v1/sections/s-9");
		expect(section.id).toBe("s-9");
	});
});

describe("createSection", () => {
	it("POSTs type + content and omits the keys the caller left unset", async () => {
		postMock.mockResolvedValue(sectionRaw({ id: "s-new", order: 4 }));

		const created = await createSection("task-1", {
			section_type: "failure_test",
			content: "Empty sections list must still render",
		});

		expect(postMock).toHaveBeenCalledWith("/api/v1/tasks/task-1/sections", {
			section_type: "failure_test",
			content: "Empty sections list must still render",
		});
		expect(created.id).toBe("s-new");
		expect(created.order).toBe(4);
	});

	it("forwards an explicit code_ref, order and checklist_state", async () => {
		postMock.mockResolvedValue(
			sectionRaw({ id: "s-c", section_type: "checklist_item" }),
		);

		await createSection("task-1", {
			section_type: "checklist_item",
			content: "Toggle me",
			order: 3,
			checklist_state: "undone",
			code_ref: { path: "src/lib/types.ts", line_start: 416 },
		});

		expect(postMock).toHaveBeenCalledWith("/api/v1/tasks/task-1/sections", {
			section_type: "checklist_item",
			content: "Toggle me",
			order: 3,
			checklist_state: "undone",
			code_ref: { path: "src/lib/types.ts", line_start: 416 },
		});
	});
});

describe("updateSection", () => {
	it("PATCHes only the changed fields and returns the stored row", async () => {
		patchMock.mockResolvedValue(
			sectionRaw({ id: "s-1", checklist_state: "done" }),
		);

		const updated = await updateSection("s-1", { checklist_state: "done" });

		expect(patchMock).toHaveBeenCalledWith("/api/v1/sections/s-1", {
			checklist_state: "done",
		});
		expect(updated.checklist_state).toBe("done");
	});

	it("sends explicit nulls so the engine clears the code reference", async () => {
		patchMock.mockResolvedValue(sectionRaw({ id: "s-1", code_ref: null }));

		const updated = await updateSection("s-1", { code_ref: null });

		expect(patchMock).toHaveBeenCalledWith("/api/v1/sections/s-1", {
			code_ref: null,
		});
		expect(updated.code_ref).toBeNull();
	});
});

describe("deleteSection", () => {
	it("DELETEs the section by id", async () => {
		deleteMock.mockResolvedValue({ message: "Section deleted" });
		await deleteSection("s-3");
		expect(deleteMock).toHaveBeenCalledWith("/api/v1/sections/s-3");
	});
});
