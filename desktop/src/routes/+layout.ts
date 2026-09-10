// The desktop client is a single-page app: the Tauri window loads the static
// build and all data comes from the Crystalline HTTP API.
export const ssr = false;
export const prerender = true;
export const trailingSlash = "always";
