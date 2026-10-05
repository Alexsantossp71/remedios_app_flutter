import { test, expect } from '@playwright/test';
import { waitForAppReady } from '../utils/helpers';

test.describe('App Setup and Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
  });

  test('app loads successfully', async ({ page }) => {
    // Verify app title
    await expect(page.locator('text=Remédio na Hora')).toBeVisible();

    // Verify bottom navigation exists
    const bottomNav = page.locator('nav, [role="navigation"]').first();
    await expect(bottomNav).toBeVisible();
  });

  test('all navigation tabs are visible and clickable', async ({ page }) => {
    const tabs = ['Hoje', 'Medicamentos', 'Médicos', 'Consultas', 'Planos', 'Perfil'];

    for (const tab of tabs) {
      const tabElement = page.locator(`text=${tab}`).first();
      await expect(tabElement).toBeVisible();
      await expect(tabElement).toBeEnabled();
    }
  });

  test('navigate to each tab successfully', async ({ page }) => {
    const tabTests = [
      { tab: 'Hoje', expected: 'Hoje' },
      { tab: 'Medicamentos', expected: 'Seus medicamentos' },
      { tab: 'Médicos', expected: 'Seus médicos' },
      { tab: 'Consultas', expected: 'Suas consultas' },
      { tab: 'Planos', expected: 'Seus planos de saúde' },
      { tab: 'Perfil', expected: 'Seu perfil' }
    ];

    for (const { tab, expected } of tabTests) {
      await page.click(`text=${tab}`);
      await page.waitForTimeout(500);

      await expect(page.locator(`text=${expected}`)).toBeVisible({ timeout: 5000 });
    }
  });

  test('app state persists after page reload', async ({ page }) => {
    // Navigate to Médicos tab
    await page.click('text=Médicos');
    await page.waitForTimeout(500);

    // Reload page
    await page.reload();
    await waitForAppReady(page);

    // Should still be on Médicos tab (state restored)
    await expect(page.locator('text=Seus médicos')).toBeVisible();
  });

  test('take screenshot of main screens', async ({ page }) => {
    const tabs = ['Hoje', 'Medicamentos', 'Médicos', 'Consultas', 'Planos', 'Perfil'];

    for (const tab of tabs) {
      await page.click(`text=${tab}`);
      await page.waitForTimeout(500);

      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      await page.screenshot({
        path: `fixtures/screenshots/${tab.toLowerCase()}-${timestamp}.png`,
        fullPage: true
      });
    }
  });
});
