import { test, expect } from '@playwright/test';
import { waitForAppReady } from '../utils/helpers';

// O app foi refatorado para 4 abas (Hoje, Tratamentos, Consultas, Perfil)
// após a decomposição dos god-files (P2-1). As suítes de doctors/medicines/
// consultations/health-plans ainda referenciam a UI de 6 abas e precisam de
// sincronização antes de voltarem ao CI — ver .github/workflows/e2e.yml.

const TABS = ['Hoje', 'Tratamentos', 'Consultas', 'Perfil'] as const;

test.describe('App Setup and Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
  });

  test('app loads successfully with the bottom navigation', async ({ page }) => {
    // document.title is set by the RemediosApp MaterialApp ("Remédio na Hora")
    // once the main shell renders — proves the gate completed and bootstrap ran.
    await expect.poll(() => page.title(), { timeout: 15000 }).toBe('Remédio na Hora');

    // Bottom navigation is a tablist with the 4 tabs.
    const tabs = page.getByRole('tab');
    await expect(tabs).toHaveCount(TABS.length);
  });

  test('all navigation tabs are visible', async ({ page }) => {
    for (const tab of TABS) {
      const tabElement = page.getByRole('tab', { name: tab });
      await expect(tabElement).toBeVisible();
      await expect(tabElement).toBeEnabled();
    }
  });

  test('navigate to each tab successfully', async ({ page }) => {
    for (const tab of TABS) {
      const tabElement = page.getByRole('tab', { name: tab });
      await tabElement.click();
      await page.waitForTimeout(500);
      // The clicked tab becomes the selected one.
      await expect(tabElement).toHaveAttribute('aria-selected', 'true');
    }
  });

  test('app reloads cleanly after the database is set up', async ({ page }) => {
    // The encrypted database key persists in IndexedDB across reloads; the
    // app should boot back into the main shell (unlock flow handled by
    // waitForAppReady) without losing the session.
    await page.reload();
    await waitForAppReady(page);

    // Main shell is back: title set and the default Hoje tab is selected.
    await expect.poll(() => page.title(), { timeout: 15000 }).toBe('Remédio na Hora');
    await expect(
      page.getByRole('tab', { name: 'Hoje' }),
    ).toHaveAttribute('aria-selected', 'true');
  });

  test('take screenshot of main screens', async ({ page }) => {
    for (const tab of TABS) {
      await page.getByRole('tab', { name: tab }).click();
      await page.waitForTimeout(500);

      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      await page.screenshot({
        path: `fixtures/screenshots/${tab.toLowerCase()}-${timestamp}.png`,
        fullPage: true,
      });
    }
  });
});
