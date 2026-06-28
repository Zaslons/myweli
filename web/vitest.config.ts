import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    // Unit/component only; Playwright e2e (tests/e2e/*.spec.ts) runs separately.
    include: ['tests/**/*.test.{ts,tsx}'],
  },
});
