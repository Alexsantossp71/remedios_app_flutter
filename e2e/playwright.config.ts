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
    // 127.0.0.1 explícito: "localhost" pode resolver para ::1 (IPv6) e o
    // http-server escuta apenas IPv4 — o mesmo sintoma quebrou o primeiro
    // run do e2e em CI (P3-3).
    baseURL: 'http://127.0.0.1:5000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    // Vídeo é o artefato mais pesado do report; em CI fica desligado para
    // não estourar memória/disco em runs longos.
    video: process.env.CI ? 'off' : 'retain-on-failure',
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

  // O Playwright gerencia o servidor do build release: se já houver um
  // servidor na porta (ex.: `flutter run -d web-server --web-port=5000`
  // para e2e em modo dev, ou o servidor do CI), ele é reutilizado.
  webServer: {
    command: [
      'ls ../build/web/index.html >/dev/null 2>&1 ||',
      '(echo "Build web ausente: rode flutter build web --release antes" && exit 1);',
      'npx -y http-server ../build/web -p 5000 -a 127.0.0.1 -c-1 --silent',
    ].join(' '),
    url: 'http://127.0.0.1:5000',
    reuseExistingServer: true,
    timeout: 60000,
  },
});
