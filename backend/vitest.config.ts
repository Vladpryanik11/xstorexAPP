import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    testTimeout: 30_000,
    hookTimeout: 60_000,
    // Each test file boots its own in-memory PGlite; keep parallelism modest.
    maxWorkers: 4,
  },
});
