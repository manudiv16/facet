import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// Standalone config for unit tests (pure helpers + stores). Keeping it separate
// from vite.config.ts avoids booting the full SvelteKit plugin for node tests.
export default defineConfig({
	test: {
		environment: "node",
		include: ["src/**/*.test.ts"],
	},
	resolve: {
		alias: {
			$lib: fileURLToPath(new URL("./src/lib", import.meta.url)),
			$stores: fileURLToPath(new URL("./src/stores", import.meta.url)),
		},
	},
});
