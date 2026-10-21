// The portal must already be running (serve.sh). One browser, Chromium; screenshots kept only when a test fails.
import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.mjs',
  timeout: 60_000,
  workers: 2,
  reporter: [['list']],
  use: { baseURL: 'http://127.0.0.1:8013/admin/', viewport: { width: 1440, height: 900 }, screenshot: 'only-on-failure' },
});
