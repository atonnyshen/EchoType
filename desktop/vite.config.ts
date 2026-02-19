import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const host = process.env.TAURI_DEV_HOST;

export default defineConfig(async () => ({
  plugins: [react()],

  // 防止 Vite 覆寫 Tauri 的 `Escape` 鍵行為
  clearScreen: false,

  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 讓 Vite 忽略 src-tauri 目錄
      ignored: ["**/src-tauri/**"],
    },
  },

  envPrefix: ["VITE_", "TAURI_ENV_*"],

  build: {
    // Tauri 在 Windows 使用 edge，在 macOS 使用 WebKit
    target: process.env.TAURI_ENV_PLATFORM == "windows" ? "chrome105" : "safari16",
    // 開發模式不壓縮，加快重建速度
    minify: !process.env.TAURI_ENV_DEBUG ? "esbuild" : false,
    // 在 debug 模式生成 sourcemap
    sourcemap: !!process.env.TAURI_ENV_DEBUG,
    rollupOptions: {
      output: {
        manualChunks: {
          react: ["react", "react-dom"],
          charts: ["echarts", "echarts-for-react"],
          animation: ["framer-motion"],
        },
      },
    },
  },
}));
