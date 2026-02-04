import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['test/javascript/**/*.test.ts'],
    globals: true,
    setupFiles: ['test/javascript/setup.ts'],
    coverage: {
      provider: 'v8',
      include: ['app/javascript/**/*.ts'],
      exclude: ['app/javascript/controllers/index.ts', 'app/javascript/controllers/application.ts'],
      reporter: ['text', 'html'],
    },
  },
  resolve: {
    alias: {
      '@': '/app/javascript',
    },
  },
})
