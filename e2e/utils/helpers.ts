import { Page } from '@playwright/test';

/**
 * Wait for Flutter app to be fully loaded.
 * Strategy: Flutter web renders inside <flutter-view> shadow DOM.
 * We wait for:
 *  1. flutter-view element present
 *  2. shadow root has rendered text (not empty)
 *  3. document.title is set (AppBar title)
 */
export async function waitForAppReady(page: Page) {
  // Wait for flutter-view element
  await page.waitForSelector('flutter-view', { timeout: 60000 });

  // Wait for shadow DOM to have rendered text content
  await page.waitForFunction(() => {
    const fv = document.querySelector('flutter-view') as HTMLElement;
    if (!fv?.shadowRoot) return false;
    const text = fv.shadowRoot.textContent?.trim();
    return text && text.length > 10;
  }, { timeout: 120000 });

  // Wait for document title to be set (proves AppBar rendered)
  await page.waitForFunction(() => document.title && document.title.length > 0, {
    timeout: 60000,
  });

  // Extra wait for SQLite to initialize
  await page.waitForTimeout(3000);
}

/**
 * Enable Flutter semantics tree so text is exposed to Playwright.
 * This calls SemanticsBinding to populate flt-semantics nodes.
 */
export async function enableSemantics(page: Page) {
  await page.evaluate(() => {
    // Enable semantics programmatically
    (window as any)._flutter?.loader?.loadEntrypoint?.({});
    // Try to access SemanticsBinding
    const sb = (window as any).SemanticsBinding;
    if (sb?.instance) {
      sb.instance.setSemanticsEnabled(true);
    }
    // Alternative: dispatch accessibility event
    const fv = document.querySelector('flutter-view');
    if (fv?.shadowRoot) {
      // Click on the shadow root to trigger semantics
      fv.shadowRoot.dispatchEvent(new Event('tap', { bubbles: true }));
    }
  });
  await page.waitForTimeout(2000);
}

/**
 * Get text content from Flutter's shadow DOM.
 */
export async function getFlutterText(page: Page): Promise<string> {
  return page.evaluate(() => {
    const fv = document.querySelector('flutter-view') as HTMLElement;
    if (!fv?.shadowRoot) return '';
    return fv.shadowRoot.textContent?.trim() || '';
  });
}

/**
 * Find an element inside flutter-view shadow DOM by text content.
 * Returns the element if found, null otherwise.
 */
export async function findInShadow(page: Page, text: string): Promise<string> {
  return page.evaluate(
    (t) => {
      const fv = document.querySelector('flutter-view') as HTMLElement;
      if (!fv?.shadowRoot) return 'not-found';
      const walker = document.createTreeWalker(
        fv.shadowRoot,
        NodeFilter.SHOW_TEXT,
        null
      );
      let node: Node | null;
      while ((node = walker.nextNode())) {
        if (node.textContent?.trim() === t) {
          // Return the parent element's outerHTML for inspection
          return 'found:' + node.parentElement?.tagName + ':' + node.parentElement?.className;
        }
      }
      return 'not-found';
    },
    text
  );
}

/**
 * Click a text element inside Flutter's shadow DOM.
 * Searches shadow DOM for the text and clicks its parent element.
 */
export async function flutterClick(page: Page, text: string) {
  await page.evaluate((t) => {
    const fv = document.querySelector('flutter-view') as HTMLElement;
    if (!fv?.shadowRoot) throw new Error('flutter-view shadow root not found');
    const shadow = fv.shadowRoot;
    const all = shadow.querySelectorAll('*');
    for (const el of all) {
      if (
        el.textContent?.trim() === t ||
        el.getAttribute('aria-label') === t
      ) {
        (el as HTMLElement).click();
        return;
      }
    }
    throw new Error(`Text "${t}" not found in shadow DOM`);
  }, text);
}

/**
 * Fill a text field inside Flutter's shadow DOM by its label/placeholder.
 */
export async function flutterFill(
  page: Page,
  label: string,
  value: string
) {
  await page.evaluate(
    ([l, v]) => {
      const fv = document.querySelector('flutter-view') as HTMLElement;
      if (!fv?.shadowRoot) throw new Error('flutter-view shadow root not found');
      const inputs = fv.shadowRoot.querySelectorAll(
        'input, textarea, [contenteditable="true"]'
      );
      for (const input of inputs) {
        const inp = input as HTMLInputElement;
        if (
          inp.placeholder === l ||
          inp.getAttribute('aria-label') === l ||
          inp.id === l
        ) {
          inp.focus();
          inp.value = v;
          inp.dispatchEvent(new Event('input', { bubbles: true }));
          inp.dispatchEvent(new Event('change', { bubbles: true }));
          return;
        }
      }
      throw new Error(`Input "${l}" not found in shadow DOM`);
    },
    [label, value]
  );
}

/**
 * Clear all data from the app (reset state).
 */
export async function clearAppData(page: Page) {
  await page.click('text=Perfil');
  await page.waitForTimeout(500);
  const clearButton = page.locator('text=Limpar todos os dados');
  if (await clearButton.isVisible()) {
    await clearButton.click();
    await page.waitForTimeout(500);
    const confirmBtn = page.locator('text=Confirmar');
    if (await confirmBtn.isVisible()) {
      await confirmBtn.click();
      await page.waitForTimeout(1000);
    }
  }
}

/**
 * Navigate to a specific tab (bottom navigation).
 */
export async function navigateToTab(page: Page, tabName: string) {
  await page.click(`text=${tabName}`);
  await page.waitForTimeout(500);
}

/**
 * Fill a text field by placeholder (standard DOM fallback).
 */
export async function fillField(page: Page, placeholder: string, value: string) {
  const field = page.locator(`[placeholder="${placeholder}"]`);
  if (await field.isVisible({ timeout: 3000 }).catch(() => false)) {
    await field.clear();
    await field.fill(value);
  } else {
    await flutterFill(page, placeholder, value);
  }
}

/**
 * Select an option from a dropdown.
 */
export async function selectDropdownOption(
  page: Page,
  label: string,
  value: string
) {
  const dropdown = page.locator(`text=${label}`).first();
  await dropdown.click();
  await page.waitForTimeout(300);
  await page.click(`text=${value}`);
}

/**
 * Take a screenshot with timestamp.
 */
export async function takeScreenshot(page: Page, name: string) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  await page.screenshot({
    path: `fixtures/screenshots/${name}-${timestamp}.png`,
    fullPage: true,
  });
}

/**
 * Generate a random Brazilian phone number.
 */
export function generatePhone(): string {
  const ddd = Math.floor(Math.random() * 89) + 11;
  const number = Math.floor(Math.random() * 90000000) + 10000000;
  return `(${ddd}) 9${number}`;
}

/**
 * Generate a random CRM number.
 */
export function generateCRM(): string {
  return Math.floor(Math.random() * 99999) + 10000;
}