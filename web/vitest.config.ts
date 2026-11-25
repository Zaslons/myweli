import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// `npm run test:stress`: React's Scheduler yields after every task — the timing
// that, on a loaded runner, lets a test read the page before an effect ran
// (tests/support/scheduler-stress.ts).
const schedulerStress = process.env.MYWELI_SCHEDULER_STRESS === '1';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: [
      './tests/setup.ts',
      ...(schedulerStress ? ['./tests/support/scheduler-stress.ts'] : []),
    ],
    // Unit/component only; Playwright e2e (tests/e2e/*.spec.ts) runs separately.
    include: ['tests/**/*.test.{ts,tsx}'],
  },
});
