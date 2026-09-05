import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// Single self-contained index.html so WKWebView can load it from file:// with no CORS issues.
export default defineConfig({
  base: './',
  plugins: [viteSingleFile()],
  build: { outDir: 'dist', emptyOutDir: true, minify: true, assetsInlineLimit: 30_000_000 },
  assetsInclude: ['**/*.glb'],
})
