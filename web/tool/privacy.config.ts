import { defineConfig, devices } from '@playwright/test';

/// A config with NO `webServer`: these checks run against a deployed url, not a
/// build. Sharing `playwright.config.ts` would start the stub and a local build
/// and then quietly measure those instead of production.
export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  retries: 0,
  reporter: 'line',
  use: { ...devices['Desktop Chrome'], trace: 'retain-on-failure' },
});
