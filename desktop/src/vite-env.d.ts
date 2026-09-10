/// <reference types="vite/client" />

interface ImportMetaEnv {
	readonly VITE_CRYSTALLINE_URL?: string;
	readonly VITE_CRYSTALLINE_TOKEN?: string;
}

interface ImportMeta {
	readonly env: ImportMetaEnv;
}
