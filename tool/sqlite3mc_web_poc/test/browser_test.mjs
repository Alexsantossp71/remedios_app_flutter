import { chromium } from 'playwright';

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  page.on('pageerror', error => {
    throw error;
  });

  for (const visit of [1, 2]) {
    await page.goto('http://127.0.0.1:4173/', { waitUntil: 'networkidle' });
    await page.locator('#result').waitFor({ state: 'visible' });
    await page.waitForFunction(
      () => document.querySelector('#result')?.textContent?.startsWith('PASS:') ||
            document.querySelector('#result')?.textContent?.startsWith('FAIL:'),
      null,
      { timeout: 30000 },
    );
    const result = await page.locator('#result').textContent();
    if (!result.startsWith('PASS:')) {
      throw new Error(`Visit ${visit} failed: ${result}`);
    }
    console.log(`Visit ${visit}: ${result}`);
  }
} finally {
  await browser.close();
}
