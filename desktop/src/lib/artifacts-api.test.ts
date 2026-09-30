// Acceptance tests for the artifacts client (`$lib/artifacts-api`).
//
// The transport is mocked so each assertion can fail on a real regression: the
// four routes and their verbs, percent-encoding of logical names (the engine
// decodes the path segment), the `{ content }` envelope the PUT handler
// requires, and pass-through of arbitrary JSON values.
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./api", () => ({
	api: {
		get: vi.fn(),
		put: vi.fn(),
		delete: vi.fn(),
	},
}));

import { api } from "./api";
import {
	deleteArtifact,
	getArtifact,
	listArtifacts,
	normalizeArtifact,
	putArtifact,
	sortArtifacts,
} from "./artifacts-api";
import type { Artifact } from "./types";

const getMock = api.get as ReturnType<typeof vi.fn>;
const putMock = api.put as ReturnType<typeof vi.fn>;
const deleteMock = api.delete as ReturnType<typeof vi.fn>;

beforeEach(() => {
	getMock.mockReset();
	putMock.mockReset();
	deleteMock.mockReset();
});

/** A Crystalline artifact wire row. */
function artifactRaw(overrides: Record<string, unknown> = {}): Record<string, unknown> {
	return {
		id: "artifact-1",
		task_id: "task-1",
		logical_name: "spec",
		content: { goal: "ship it" },
		created_at: 1_700_000_000,
		updated_at: 1_700_000_100,
		...overrides,
	};
}

describe("normalizeArtifact", () => {
	it("keeps falsy JSON content instead of nullifying it", () => {
		expect(normalizeArtifact(artifactRaw({ content: false }) as never).content).toBe(false);
		expect(normalizeArtifact(artifactRaw({ content: 0 }) as never).content).toBe(0);
		expect(normalizeArtifact(artifactRaw({ content: "" }) as never).content).toBe("");
	});

	it("falls back to null content and epoch 0 timestamps when absent", () => {
		const artifact = normalizeArtifact({ id: "a-1" });
		expect(artifact.content).toBeNull();
		expect(artifact.created_at).toBe(0);
		expect(artifact.updated_at).toBe(0);
		expect(artifact.logical_name).toBe("");
	});
});

describe("sortArtifacts", () => {
	it("orders by logical name without mutating the input", () => {
		const rows = [
			{ logical_name: "zeta" },
			{ logical_name: "alpha" },
		] as Artifact[];
		expect(sortArtifacts(rows).map((a) => a.logical_name)).toEqual([
			"alpha",
			"zeta",
		]);
		expect(rows.map((a) => a.logical_name)).toEqual(["zeta", "alpha"]);
	});
});

describe("listArtifacts", () => {
	it("GETs the task's artifacts in logical-name order", async () => {
		getMock.mockResolvedValue([
			artifactRaw({ id: "a-2", logical_name: "zzz" }),
			artifactRaw({ id: "a-1", logical_name: "aaa" }),
		]);

		const artifacts = await listArtifacts("task-1");

		expect(getMock).toHaveBeenCalledWith("/api/v1/tasks/task-1/artifacts");
		expect(artifacts.map((artifact) => artifact.logical_name)).toEqual([
			"aaa",
			"zzz",
		]);
	});
});

describe("getArtifact", () => {
	it("GETs one artifact by percent-encoded logical name", async () => {
		getMock.mockResolvedValue(artifactRaw({ logical_name: "spec draft.json" }));

		const artifact = await getArtifact("task-1", "spec draft.json");

		expect(getMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task-1/artifacts/spec%20draft.json",
		);
		expect(artifact.logical_name).toBe("spec draft.json");
	});
});

describe("putArtifact", () => {
	it("PUTs the { content } envelope and returns the stored row", async () => {
		putMock.mockResolvedValue(
			artifactRaw({ logical_name: "coverage", content: [1, 2] }),
		);

		const saved = await putArtifact("task-1", "coverage", [1, 2]);

		expect(putMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task-1/artifacts/coverage",
			{ content: [1, 2] },
		);
		expect(saved.content).toEqual([1, 2]);
	});

	it("preserves a null content value", async () => {
		putMock.mockResolvedValue(artifactRaw({ content: null }));
		const saved = await putArtifact("task-1", "cleared", null);
		expect(putMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task-1/artifacts/cleared",
			{ content: null },
		);
		expect(saved.content).toBeNull();
	});
});

describe("deleteArtifact", () => {
	it("DELETEs by task and logical name", async () => {
		deleteMock.mockResolvedValue({ message: "Artifact deleted" });
		await deleteArtifact("task-1", "spec/v2");
		expect(deleteMock).toHaveBeenCalledWith(
			"/api/v1/tasks/task-1/artifacts/spec%2Fv2",
		);
	});
});
