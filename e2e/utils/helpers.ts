import { Page, type Locator } from '@playwright/test';

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

/** Mount the engine, enable the semantics tree and wait for the first
 * rendered text.
 *
 * Shared prologue of every E2E drive of the app: clicking the semantics
 * placeholder BEFORE the engine finishes mounting is a no-op (the element
 * does not exist yet) and leaves the DOM blind — the app renders to canvas
 * and exposes no text. So: wait for <flutter-view>, click the placeholder,
 * then wait until <flt-semantics-host> actually carries text.
 */
export async function bootAndEnableSemantics(page: Page) {
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
}

/** Wait for the Flutter app to be fully loaded and interactive.
 *
 * Returns which vault-prompt flow was completed, if any:
 *  - 'setup'  → the 6-digit PIN vault was created (first interaction on the
 *               device);
 *  - 'unlock' → the password fallback was answered (device mirror missing);
 *  - 'none'   → no prompt was shown (returning session auto-unlocked).
 */
export async function waitForAppReady(
  page: Page,
): Promise<'setup' | 'unlock' | 'none'> {
  // 1-3. Engine mount + semantics on + first rendered text.
  await bootAndEnableSemantics(page);

  // 3.5 On web the BootLoader (0–100%, ~2s) STOPS at 100% and shows two
  //     buttons: "Entrar" (vault setup on first interaction, or straight in
  //     when the device mirror unlocks the vault) and "Demo (não salva
  //     dados)" (in-memory mock). The E2E suite exercises the persistent
  //     flow, so click "Entrar" whenever the boot screen is up. Idempotent:
  //     no-op if the button is not rendered.
  await ensureWelcomePassed(page);

  // 4. On web with a fresh browser profile, the app boots into the
  //    DatabaseUnlockGate ("Proteger seu banco de dados") and asks for a
  //    6-digit PIN ONCE (first interaction on this device). Returning
  //    sessions auto-unlock from the device key mirror and skip the gate
  //    entirely. Idempotent — reports which flow ran ('none' when skipped).
  const vaultFlow = await ensureDatabaseUnlocked(page);

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

  return vaultFlow;
}

/** Dismiss the BootLoader screen by clicking "Entrar".
 *
 * The web boot flow is BootLoader (0–100%) → STOP with buttons "Entrar" /
 * "Demo (não salva dados)" on the same screen → "Entrar" leads to the
 * DatabaseUnlockGate (first interaction on the device) or straight into the
 * main shell (returning device, auto-unlock). Idempotent: if the button is
 * not rendered within the timeout (flow changed or already past it),
 * returns without clicking so the caller can proceed.
 */
export async function ensureWelcomePassed(page: Page) {
  const enter = page.getByRole('button', { name: /^Entrar$/ }).first();
  try {
    await enter.waitFor({ state: 'visible', timeout: 30000 });
    await enter.click();
  } catch {
    // Boot screen not present — nothing to dismiss.
  }
}

/** Fill a Flutter web text field reliably and VERIFY the value stuck.
 *
 * Flutter web keeps a single native <input> in flt-text-editing-host and
 * re-parents it into whichever semantics node has focus. Two races make a
 * plain locator.fill() unreliable here:
 *  1. Events dispatched right after the click can arrive BEFORE Flutter
 *     rebinds the input — the DOM value sticks, but the framework-side
 *     controller stays EMPTY (observed as a silently invalid "Confirmar
 *     PIN" on submit);
 *  2. A fill issued during the swap can land on the OLD input.
 * So: click → settle → type with real keyboard events → read back → retry.
 */
export async function fillFlutterField(
  page: Page,
  locator: Locator,
  value: string,
  tries = 6,
) {
  for (let attempt = 1; attempt <= tries; attempt++) {
    await locator.click();
    // Let Flutter bind the native input to this field before typing.
    await page.waitForTimeout(400);
    try {
      await locator.fill('');
      await page.waitForTimeout(150);
    } catch {
      // Nothing to clear (field may not host the input yet).
    }
    await locator.pressSequentially(value, { delay: 40 });
    const current = await locator
      .inputValue()
      .catch(() => null); // no native input in the node yet
    if (current === value) return;
    await page.waitForTimeout(400);
  }
  throw new Error(
    `Flutter field did not accept value "${value}" after ${tries} attempts`,
  );
}

/** Complete the web DatabaseUnlockGate flow if present; report what ran.
 *
 * Product rule: the PIN is asked ONLY on the first interaction with the app
 * on a device (vault setup) and for backup recovery. Returns:
 *  - 'setup'  → fresh profile: created the vault with the 6-digit PIN.
 *  - 'unlock' → rare fallback: envelope exists but the device key mirror is
 *               missing, so the password was requested.
 *  - 'none'   → returning session: the gate auto-unlocked from the device
 *               mirror ("Abrindo seu banco…") — no prompt shown.
 *
 * After vault creation the app shows the one-time profile invitation
 * ("Quem vai usar o app?") before the diary. By default this helper
 * dismisses it ("Pular por agora") so suites land in the main shell; pass
 * `{ dismissProfileInvitation: false }` to keep it on screen (used by the
 * invitation tests themselves).
 *
 * Idempotent: safe to call on every load.
 */
export async function ensureDatabaseUnlocked(
  page: Page,
  opts: { dismissProfileInvitation?: boolean } = {},
): Promise<'setup' | 'unlock' | 'none'> {
  // Wait until either the vault gate renders (first interaction on this
  // device → PIN setup) or the main shell is already up (returning session
  // → auto-unlock, no gate at all; RemediosApp is the ONLY MaterialApp with
  // a document title, so an empty title means the shell has not rendered).
  // The SQLite wasm worker spin-up makes the gate slow to render on busy
  // machines — a fixed 3s probe made this helper flaky ('none' while the
  // gate was still loading).
  await page
    .waitForFunction(
      () =>
        document.title === 'Remédio na Hora' ||
        (document
          .querySelector('flt-semantics-host')
          ?.textContent?.includes('Proteger seu banco de dados') ===
          true),
      undefined,
      { timeout: 20000 },
    )
    .catch(() => {});

  // Setup flow (first interaction on this device).
  const setupVisible = await page
    .locator('text=Proteger seu banco de dados')
    .isVisible({ timeout: 3000 })
    .catch(() => false);
  if (setupVisible) {
    const pin = page.locator('[aria-label="PIN do cofre (6 dígitos)"]').first();
    const confirm = page.locator('[aria-label="Confirmar PIN"]').first();
    // Click first so Flutter spawns the native input for each field, then
    // fill with read-back verification (Flutter web re-parents a single
    // native <input> — plain fill can silently miss the swap).
    await fillFlutterField(page, pin, E2E_DB_PIN);
    await fillFlutterField(page, confirm, E2E_DB_PIN);
    await page.getByRole('button', { name: 'Criar cofre e abrir o app' }).click();

    // First interaction ends with the one-time profile invitation. Skip it
    // by default; the invitation specs pass dismissProfileInvitation: false
    // (there the invitation stays up — the shell only comes after the spec
    // itself skips or saves, so the title check below does not apply).
    let invitationDismissed = false;
    if (opts.dismissProfileInvitation !== false) {
      const skip = page
        .getByRole('button', { name: 'Pular por agora' })
        .first();
      // The invitation reuses the full profile form (~1600px): in a default
      // viewport the skip button sits below the fold and the lazy ListView
      // has not built it. Wheel-scroll the screen until it shows up.
      await page.mouse.move(640, 360);
      for (let i = 0; i < 8; i++) {
        if (await skip.isVisible().catch(() => false)) break;
        await page.mouse.wheel(0, 700);
        await page.waitForTimeout(250);
      }
      try {
        await skip.waitFor({ state: 'visible', timeout: 30000 });
        await skip.click();
        invitationDismissed = true;
      } catch {
        // Invitation not rendered (older build or already dismissed) —
        // proceed to the shell anyway.
      }
    }

    // Verify the bootstrap actually ran: RemediosApp sets the document
    // title once the main shell renders. Without this check a racy fill
    // (invalid form) would keep the gate on screen and still return a
    // bogus 'setup'.
    if (invitationDismissed) {
      await page.waitForFunction(
        () => document.title === 'Remédio na Hora',
        undefined,
        { timeout: 90000 },
      );
    }
    return 'setup';
  }

  // Unlock fallback (envelope stored, device mirror missing).
  const unlockVisible = await page
    .locator('text=Banco bloqueado')
    .isVisible({ timeout: 3000 })
    .catch(() => false);
  if (unlockVisible) {
    const password = page
      .locator('[aria-label="Senha de recuperação"]')
      .first();
    await fillFlutterField(page, password, E2E_DB_PIN);
    await page.getByRole('button', { name: 'Desbloquear' }).click();
    return 'unlock';
  }

  return 'none';
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
