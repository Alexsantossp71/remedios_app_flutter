import { Page } from '@playwright/test';

/**
 * Helpers for driving the Flutter web app from Playwright.
 *
 * Flutter 3.50 web renders pixels to a canvas inside <flt-glass-pane>; the
 * DOM exposes text only through the semantics tree, which lives in the
 * light-DOM element <flt-semantics-host> (NOT inside <flutter-view>'s
 * shadow root — <flutter-view> has no shadow root in this version). The
 * semantics tree is disabled by default and is turned on by clicking the
 * <flt-semantics-placeholder> button ("Enable accessibility") that Flutter
 * injects at the top of the document. waitForAppReady() does that click
 * before waiting for any text.
 */

/** 6-digit vault PIN used to set up the encrypted database in e2e. */
const E2E_DB_PIN = '123456';

/** Wait for the Flutter app to be fully loaded and interactive. */
export async function waitForAppReady(page: Page) {
  // 1. flutter-view element present (host mounted by the engine).
  await page.waitForSelector('flutter-view', { timeout: 60000 });

  // 2. Enable the semantics tree: Flutter renders text to canvas, so the
  //    DOM only exposes <flt-semantics> text nodes after accessibility is
  //    on. Playwright is not an assistive tech, so we click the built-in
  //    <flt-semantics-placeholder> ourselves (it lives in the light DOM).
  await page.evaluate(() => {
    const ph = document.querySelector(
      'flt-semantics-placeholder',
    ) as HTMLElement | null;
    ph?.click();
  });

  // 3. Wait for <flt-semantics-host> to expose rendered text content.
  await page.waitForFunction(
    () => {
      const host = document.querySelector('flt-semantics-host');
      if (!host) return false;
      const text = host.textContent?.trim();
      return text != null && text.length > 10;
    },
    undefined,
    { timeout: 120000 },
  );

  // 3.5 On web the BootLoader (0–100%, ~2s) always dispatches to the
  //     WelcomeScreen, which offers "Começar — criar meu cofre" (persistent
  //     vault) or "Ver demo (não salva dados)" (in-memory mock). The E2E
  //     suite exercises the persistent flow, so click "Começar" whenever the
  //     welcome is up. Idempotent: no-op if the welcome is not rendered.
  await ensureWelcomePassed(page);

  // 4. On web with a fresh browser profile, the app boots into the
  //    DatabaseUnlockGate ("Proteger seu banco de dados") and requires a
  //    recovery password before the main shell loads. Complete it once per
  //    context (idempotent — if the DB is already unlocked, skip).
  await ensureDatabaseUnlocked(page);

  // 5. Wait for the main shell: AppBar title "Remédio na Hora" is set by
  //    Flutter on the first rendered frame of MainShell.
  await page.waitForFunction(
    () => !!document.title && document.title.length > 0,
    undefined,
    { timeout: 60000 },
  );

  // 6. Extra settle time for SQLite (sqlite3mc wasm) to finish initializing
  //    before interactions start.
  await page.waitForTimeout(3000);
}

/** Dismiss the web WelcomeScreen by clicking "Começar — criar meu cofre".
 *
 * The web boot flow is BootLoader (0–100%) → WelcomeScreen →
 * DatabaseUnlockGate → main shell, and the welcome shows on every web load
 * (fresh and returning profiles alike). Idempotent: if the welcome is not
 * rendered within the timeout (flow changed or already past it), returns
 * without clicking so the caller can proceed.
 */
export async function ensureWelcomePassed(page: Page) {
  const start = page.getByRole('button', { name: /Começar/ }).first();
  try {
    await start.waitFor({ state: 'visible', timeout: 30000 });
    await start.click();
  } catch {
    // Welcome not present — nothing to dismiss.
  }
}

/** Complete the web DatabaseUnlockGate setup or unlock flow if present.
 *
 * Two flows:
 *  - Setup (fresh profile): "Proteger seu banco de dados" → 6-digit PIN +
 *    confirm + "Criar cofre e abrir o app".
 *  - Unlock (returning profile): "Banco bloqueado" → password (legacy vaults
 *    keep long passwords; new vaults use the same 6-digit PIN) +
 *    "Desbloquear".
 *
 * Idempotent: if neither prompt is visible (DB already unlocked in this
 * context), returns immediately.
 */
export async function ensureDatabaseUnlocked(page: Page) {
  // Setup flow.
  const setupVisible = await page
    .locator('text=Proteger seu banco de dados')
    .isVisible({ timeout: 3000 })
    .catch(() => false);
  if (setupVisible) {
    const pin = page.locator('[aria-label="PIN do cofre (6 dígitos)"]').first();
    const confirm = page.locator('[aria-label="Confirmar PIN"]').first();
    // Flutter web keeps a single native <input> in flt-text-editing-host and
    // reassigns it to whichever semantics textbox has focus. Click each field
    // first so Flutter spawns the native input for it, then type.
    await pin.click();
    await pin.fill(E2E_DB_PIN);
    await confirm.click();
    await confirm.fill(E2E_DB_PIN);
    await page.getByRole('button', { name: 'Criar cofre e abrir o app' }).click();
    return;
  }

  // Unlock flow (returning profile, e.g. after page.reload()).
  const unlockVisible = await page
    .locator('text=Banco bloqueado')
    .isVisible({ timeout: 3000 })
    .catch(() => false);
  if (unlockVisible) {
    const password = page.locator('[aria-label="Senha de recuperação"]').first();
    await password.click();
    await password.fill(E2E_DB_PIN);
    await page.getByRole('button', { name: 'Desbloquear' }).click();
    return;
  }
}

/** Enable Flutter's semantics tree (idempotent; also called by waitForAppReady). */
export async function enableSemantics(page: Page) {
  await page.evaluate(() => {
    const ph = document.querySelector(
      'flt-semantics-placeholder',
    ) as HTMLElement | null;
    ph?.click();
  });
  await page.waitForTimeout(500);
}

/** Get the text content rendered in the Flutter semantics tree. */
export async function getFlutterText(page: Page): Promise<string> {
  return page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host');
    return host?.textContent?.trim() || '';
  });
}

/** Find a semantics node by exact text. Returns 'found' or 'not-found'. */
export async function findInShadow(page: Page, text: string): Promise<string> {
  return page.evaluate((t) => {
    const host = document.querySelector('flt-semantics-host');
    if (!host) return 'not-found';
    const walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT);
    let node: Node | null;
    while ((node = walker.nextNode())) {
      if (node.textContent?.trim() === t) {
        return 'found:' + node.parentElement?.tagName;
      }
    }
    return 'not-found';
  }, text);
}

/** Click a Flutter semantics node by exact text or aria-label. */
export async function flutterClick(page: Page, text: string) {
  await page.evaluate((t) => {
    const host = document.querySelector('flt-semantics-host');
    if (!host) throw new Error('flt-semantics-host not found');
    const all = host.querySelectorAll('*');
    for (const el of all) {
      if (el.textContent?.trim() === t || el.getAttribute('aria-label') === t) {
        (el as HTMLElement).click();
        return;
      }
    }
    throw new Error(`Text "${t}" not found in semantics tree`);
  }, text);
}

/** Fill a Flutter text field by placeholder/aria-label/id. */
export async function flutterFill(page: Page, label: string, value: string) {
  await page.evaluate(([l, v]) => {
    // Flutter hosts native inputs inside <flt-text-editing-host> (light DOM).
    const root =
      document.querySelector('flt-text-editing-host') ?? document.body;
    const inputs = root.querySelectorAll(
      'input, textarea, [contenteditable="true"]',
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
    throw new Error(`Input "${l}" not found`);
  }, [label, value]);
}

/** Clear all data from the app (reset state). */
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

/** Navigate to a specific tab (bottom navigation). */
export async function navigateToTab(page: Page, tabName: string) {
  await page.click(`text=${tabName}`);
  await page.waitForTimeout(500);
}

/** Fill a text field by placeholder (standard DOM fallback). */
export async function fillField(page: Page, placeholder: string, value: string) {
  const field = page.locator(`[placeholder="${placeholder}"]`);
  if (await field.isVisible({ timeout: 3000 }).catch(() => false)) {
    await field.clear();
    await field.fill(value);
  } else {
    await flutterFill(page, placeholder, value);
  }
}

/** Select an option from a dropdown. */
export async function selectDropdownOption(
  page: Page,
  label: string,
  value: string,
) {
  const dropdown = page.locator(`text=${label}`).first();
  await dropdown.click();
  await page.waitForTimeout(300);
  await page.click(`text=${value}`);
}

/** Take a screenshot with timestamp. */
export async function takeScreenshot(page: Page, name: string) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  await page.screenshot({
    path: `fixtures/screenshots/${name}-${timestamp}.png`,
    fullPage: true,
  });
}

/** Generate a random Brazilian phone number. */
export function generatePhone(): string {
  const ddd = Math.floor(Math.random() * 89) + 11;
  const number = Math.floor(Math.random() * 90000000) + 10000000;
  return `(${ddd}) 9${number}`;
}

/** Generate a random CRM number. */
export function generateCRM(): string {
  return Math.floor(Math.random() * 99999) + 10000;
}
