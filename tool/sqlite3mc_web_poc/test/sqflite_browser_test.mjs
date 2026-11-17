import { chromium } from 'playwright';

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();

async function run(mode) {
  const page = await context.newPage();
  try {
    await page.goto(
      `http://127.0.0.1:4173/sqflite.html?mode=${mode}`,
      { waitUntil: 'domcontentloaded' },
    );
    await page.waitForFunction(
      () => {
        const value = document.querySelector('#result')?.textContent ?? '';
        return value.startsWith('PASS:') || value.startsWith('FAIL:');
      },
      null,
      { timeout: 30000 },
    );
    const result = await page.locator('#result').textContent();
    if (!result.startsWith('PASS:')) {
      throw new Error(`sqflite Web ${mode} failed: ${result}`);
    }
    console.log(result);
  } finally {
    await page.close();
  }
}

try {
  await run('write');
  await run('verify');
  await run('wrong-key');
} finally {
  await context.close();
  await browser.close();
}
