import { defineConfig } from '@playwright/test';

const PORT = 3000;
const STUB_PORT = 8787;
const baseURL = `http://127.0.0.1:${PORT}`;

/// Hermetic e2e: a stub API (no real backend) + the built Next app pointed at it.
/// The app fetches server-side, so the stub URL must be inlined at build time.
/// The WHOLE harness is pinned to UTC — browser (`timezoneId`) + stub + Next
/// processes (`TZ`) — so date-boundary seeds are deterministic on any dev
/// machine (docs/design/timezone-salon-time.md §4; the salon zone is UTC+0).
export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: 'line',
  use: { baseURL, timezoneId: 'UTC' },
  webServer: [
    {
      command: `node tests/e2e/stub-api.mjs`,
      port: STUB_PORT,
      reuseExistingServer: !process.env.CI,
      env: { TZ: 'UTC' },
    },
    {
      command: `npm run build && npm run start`,
      url: baseURL,
      timeout: 180_000,
      reuseExistingServer: !process.env.CI,
      env: {
        NEXT_PUBLIC_API_BASE_URL: `http://127.0.0.1:${STUB_PORT}`,
        NEXT_PUBLIC_SITE_URL: baseURL,
        TZ: 'UTC',
      },
    },
  ],
});
