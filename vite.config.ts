import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";
import { fileURLToPath } from "node:url";

const host = process.env.TAURI_DEV_HOST;
const isE2E = process.env.VITE_E2E === "1";
const rootDir = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  resolve: {
    alias: isE2E
      ? {
          "@tauri-apps/api/core": path.resolve(
            rootDir,
            "src/mocks/tauri/core.ts"
          ),
          "@tauri-apps/api/event": path.resolve(
            rootDir,
            "src/mocks/tauri/event.ts"
          ),
        }
      : {},
  },
  server: {
    host: isE2E ? "127.0.0.1" : host || false,
    port: 5173,
    strictPort: true,
    watch: {
      ignored: ["**/src-tauri/**"],
    },
  },
});
