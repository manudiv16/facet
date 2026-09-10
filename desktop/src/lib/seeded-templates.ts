// Seeded flow templates.
//
// Mirrors Crystalline's prebuilt registry (`flow/templates.gleam`, issue C11).
// The picker prefers templates returned by `GET /api/v1/flow-templates`;
// this catalogue is used as a fallback when the API list is empty or
// unreachable, so the slugs are always discoverable in the UI. Node ids,
// types and transition conditions match the engine definitions.

import type { FlowTemplate } from "./types";

function step(id: string, name: string, goal: string) {
	return {
		id,
		name,
		node_type: "step" as const,
		goal,
		prompt: goal,
		child_ids: [],
		branch_rules: [],
		loop_config: null,
		agent_config: null,
		output_schema: null,
	};
}

export const SEEDED_TEMPLATES: FlowTemplate[] = [
	{
		id: "implement_review",
		slug: "implement_review",
		name: "Implement & Review",
		description:
			"Linear flow: research the codebase, implement changes, write tests, then review the result.",
		initial_node_id: "research",
		nodes: [
			step("research", "Research the codebase", "Explore the relevant codebase areas and existing patterns."),
			step("implement", "Implement the changes", "Make the required code changes following the discovered patterns."),
			step("test", "Write and run tests", "Create tests that validate the implementation and run them."),
			step("review", "Review the result", "Review all changes, check edge cases and code quality."),
		],
		transitions: [
			{ id: "t1", from_id: "research", to_id: "implement", condition: null, label: null },
			{ id: "t2", from_id: "implement", to_id: "test", condition: null, label: null },
			{ id: "t3", from_id: "test", to_id: "review", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "bugfix",
		slug: "bugfix",
		name: "Bug Fix",
		description:
			"Linear flow: reproduce the bug, diagnose the root cause, implement a fix, then verify.",
		initial_node_id: "reproduce",
		nodes: [
			step("reproduce", "Reproduce the bug", "Create a minimal reproduction and confirm the failure mode."),
			step("diagnose", "Diagnose root cause", "Trace the code to identify the root cause."),
			step("fix", "Implement the fix", "Write a targeted fix for the identified root cause."),
			step("verify", "Verify the fix", "Run the reproduction and related tests to confirm no regressions."),
		],
		transitions: [
			{ id: "t1", from_id: "reproduce", to_id: "diagnose", condition: null, label: null },
			{ id: "t2", from_id: "diagnose", to_id: "fix", condition: null, label: null },
			{ id: "t3", from_id: "fix", to_id: "verify", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "refactor_loop",
		slug: "refactor_loop",
		name: "Refactor Loop",
		description:
			"Loop-based flow: refactor a file and run tests until they pass (max 50 iterations).",
		initial_node_id: "identify_file",
		nodes: [
			step("identify_file", "Identify file to refactor", "Determine which file needs refactoring."),
			{
				id: "refactor_loop",
				name: "Refactor & Test Loop",
				node_type: "loop",
				goal: "Refactor the file and run tests until all tests pass",
				prompt: null,
				child_ids: ["refactor_file", "run_tests"],
				branch_rules: [],
				loop_config: {
					max_iterations: 50,
					exit_condition: "tests_pass",
					child_ids: ["refactor_file", "run_tests"],
				},
				agent_config: null,
				output_schema: null,
			},
			step("refactor_file", "Refactor the file", "Extract functions, simplify logic, improve naming."),
			step("run_tests", "Run the test suite", "Run the suite and set tests_pass=true when green."),
			step("summarize", "Summarize refactoring", "Summarize what changed and the final test status."),
		],
		transitions: [
			{ id: "t1", from_id: "identify_file", to_id: "refactor_loop", condition: null, label: null },
			{ id: "t2", from_id: "refactor_loop", to_id: "summarize", condition: "loop_exit", label: "loop_exit" },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "review_gate",
		slug: "review_gate",
		name: "Review Gate",
		description:
			"Branching flow: approve to finish, request changes to fix and re-review, or reject to roll back.",
		initial_node_id: "review",
		nodes: [
			step("review", "Review the changes", "Examine the changes for correctness and code quality."),
			{
				id: "gate_branch",
				name: "Approval Gate",
				node_type: "branch",
				goal: "Route on the review decision",
				prompt: null,
				child_ids: [],
				branch_rules: [
					{ condition: "approved", target_id: "done" },
					{ condition: "changes_requested", target_id: "fix" },
					{ condition: "rejected", target_id: "rollback" },
				],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
			step("done", "Mark as approved", "Mark the task as complete."),
			step("fix", "Address review comments", "Make targeted changes for each comment."),
			step("re_review", "Re-review after fixes", "Verify all review comments were addressed."),
			step("rollback", "Rollback changes", "Revert the changes and document the reason."),
		],
		transitions: [
			{ id: "t1", from_id: "review", to_id: "gate_branch", condition: null, label: null },
			{ id: "t2", from_id: "gate_branch", to_id: "done", condition: "approved", label: "approved" },
			{ id: "t3", from_id: "gate_branch", to_id: "fix", condition: "changes_requested", label: "changes requested" },
			{ id: "t4", from_id: "gate_branch", to_id: "rollback", condition: "rejected", label: "rejected" },
			{ id: "t5", from_id: "fix", to_id: "re_review", condition: null, label: null },
			{ id: "t6", from_id: "re_review", to_id: "gate_branch", condition: null, label: "re-evaluate" },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "multi_file_analysis",
		slug: "multi_file_analysis",
		name: "Multi-File Analysis",
		description:
			"Parallel flow: analyze multiple files concurrently, then synthesize a unified report.",
		initial_node_id: "identify_files",
		nodes: [
			step("identify_files", "Identify files to analyze", "Determine which files need analysis."),
			{
				id: "parallel_analysis",
				name: "Parallel File Analysis",
				node_type: "parallel",
				goal: "Analyze multiple files concurrently",
				prompt: null,
				child_ids: ["analyze_file_a", "analyze_file_b", "analyze_file_c"],
				branch_rules: [],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
			step("analyze_file_a", "Analyze file A", "Check structure, dependencies and issues."),
			step("analyze_file_b", "Analyze file B", "Check structure, dependencies and issues."),
			step("analyze_file_c", "Analyze file C", "Check structure, dependencies and issues."),
			step("synthesize", "Synthesize findings", "Combine results into a unified report."),
		],
		transitions: [
			{ id: "t1", from_id: "identify_files", to_id: "parallel_analysis", condition: null, label: null },
			{ id: "t2", from_id: "parallel_analysis", to_id: "synthesize", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
	{
		id: "design_implement",
		slug: "design_implement",
		name: "Design & Implement",
		description:
			"Human-in-the-loop flow: research, design, get approval, implement, then test.",
		initial_node_id: "research",
		nodes: [
			step("research", "Research requirements", "Understand requirements and constraints."),
			step("design", "Design the solution", "Write a design document with approach and trade-offs."),
			{
				id: "design_review",
				name: "Design Review",
				node_type: "human_input",
				goal: "Get human approval on the design before implementation",
				prompt: "Review the proposed design. Reply 'approve' to proceed or give feedback.",
				child_ids: [],
				branch_rules: [],
				loop_config: null,
				agent_config: null,
				output_schema: null,
			},
			step("implement", "Implement the solution", "Implement the approved design."),
			step("test", "Test the implementation", "Write and run tests validating the design."),
		],
		transitions: [
			{ id: "t1", from_id: "research", to_id: "design", condition: null, label: null },
			{ id: "t2", from_id: "design", to_id: "design_review", condition: null, label: null },
			{ id: "t3", from_id: "design_review", to_id: "implement", condition: null, label: null },
			{ id: "t4", from_id: "implement", to_id: "test", condition: null, label: null },
		],
		on_done_template_id: null,
		on_reject_template_id: null,
	},
];

export const SEEDED_TEMPLATE_SLUGS = SEEDED_TEMPLATES.map((t) => t.slug);
