// Playwright test-runner config — bootstrapped on first use (per docs/runbooks/testing.md).
// Tests live in tests/ and are behavioral/visual (rendered storefront) or structural
// (theme files), and run with: npx playwright test
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: 'tests',
  reporter: 'list',
  use: { headless: true },
});
