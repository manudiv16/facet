import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig } from "vite";

// Tauri expects a fixed dev-server port (see devUrl in src-tauri/tauri.conf.json).
export default defineConfig({
	plugins: [sveltekit()],
	clearScreen: false,
	server: {
		port: 1420,
		strictPort: true,
		watch: {
			// The Rust source is watched by `tauri dev`, not Vite.
			ignored: ["**/src-tauri/**"],
		},
	},
});
