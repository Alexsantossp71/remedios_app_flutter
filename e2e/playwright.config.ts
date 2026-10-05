import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  // Override global test timeout (defaults to 30s, Flutter apps are slow)
  timeout: 240000,
  expect: {
    timeout: 15000,
  },
  reporter: [
    ['html', { outputFolder: 'playwright-report' }],
    ['json', { outputFile: 'test-results/results.json' }],
    ['list']
  ],
  use: {
    baseURL: 'http://localhost:5000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 60000,
    navigationTimeout: 120000,
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    // Uncomment to test on other browsers
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] },
    // },
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] },
    // },
  ],

  // Run local dev server before starting tests
  // IMPORTANT: Start Flutter manually before running tests:
  // 1. Terminal 1: flutter run -d web-server --web-port=5000
  // 2. Terminal 2: cd e2e && npm test
  webServer: {
    command: 'echo "Flutter server must be started manually" && exit 1',
    url: 'http://localhost:5000',
    reuseExistingServer: true,
    timeout: 10000,
  },
});
