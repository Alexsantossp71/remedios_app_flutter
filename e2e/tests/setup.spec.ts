import { test, expect, type Page } from '@playwright/test';
import {
  waitForAppReady,
  bootAndEnableSemantics,
  ensureWelcomePassed,
  ensureDatabaseUnlocked,
  fillFlutterField,
} from '../utils/helpers';

// O app foi refatorado para 4 abas (Hoje, Tratamentos, Consultas, Perfil)
// após a decomposição dos god-files (P2-1). As suítes de doctors/medicines/
// consultations/health-plans ainda referenciam a UI de 6 abas e precisam de
// sincronização antes de voltarem ao CI — ver .github/workflows/e2e.yml.

const TABS = ['Hoje', 'Tratamentos', 'Consultas', 'Perfil'] as const;

// Vault-prompt flow of the first waitForAppReady in this test (fresh browser
// context): 'setup' = 6-digit PIN asked, 'none' = auto-unlocked without PIN.
let firstRunFlow: 'setup' | 'unlock' | 'none' = 'none';

test.describe('App Setup and Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    firstRunFlow = await waitForAppReady(page);
  });

  test('app loads successfully with the bottom navigation', async ({ page }) => {
    // document.title is set by the RemediosApp MaterialApp ("Remédio na Hora")
    // once the main shell renders — proves the gate completed and bootstrap ran.
    await expect.poll(() => page.title(), { timeout: 15000 }).toBe('Remédio na Hora');

    // First interaction on this device: the vault setup MUST ask the PIN.
    expect(firstRunFlow).toBe('setup');

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
    // First interaction on this device asked for the 6-digit PIN (vault setup).
    expect(firstRunFlow).toBe('setup');

    await page.reload();

    // Returning session: the device key mirror auto-unlocks the vault — the
    // PIN must NOT be asked again on this device ('none' = gate skipped).
    const reloadFlow = await waitForAppReady(page);
    expect(reloadFlow).toBe('none');

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

test.describe('First-run profile invitation (after vault creation)', () => {
  // Tall viewport: the invitation reuses the full profile form (~1600px) —
  // in the default 1280x720 the "Salvar e começar" button, the LGPD consent
  // and "Pular por agora" sit below the fold and are NOT built by the lazy
  // ListView (absent from the semantics tree).
  test.use({ viewport: { width: 1280, height: 3200 } });

  // Fresh browser context per test: the vault is created with the E2E PIN,
  // so every test here walks the real first interaction. Unlike the suite
  // above, the invitation is kept on screen (dismissProfileInvitation:
  // false) so it can be asserted directly.
  async function bootToInvitation(page: Page) {
    await page.goto('/');
    // Same robust prologue as waitForAppReady (engine mount → semantics on →
    // first rendered text): clicking the placeholder before the engine
    // mounts is a no-op and leaves the DOM blind, silently skipping Entrar
    // and the vault setup.
    await bootAndEnableSemantics(page);
    await ensureWelcomePassed(page);
    const flow = await ensureDatabaseUnlocked(page, {
      dismissProfileInvitation: false,
    });
    expect(flow).toBe('setup');
    await expect(page.getByText('Quem vai usar o app?')).toBeVisible({
      timeout: 30000,
    });
  }

  test('invites once after the vault is created; skip lands in the diary',
    async ({ page }) => {
      await bootToInvitation(page);

      // Both exits are offered: save or skip.
      await expect(
        page.getByRole('button', { name: 'Salvar e começar' }),
      ).toBeVisible();
      await expect(
        page.getByRole('button', { name: 'Pular por agora' }),
      ).toBeVisible();

      // Skipping goes straight to the diary (MainShell).
      await page.getByRole('button', { name: 'Pular por agora' }).click();
      await expect
        .poll(() => page.title(), { timeout: 30000 })
        .toBe('Remédio na Hora');
      await expect(page.getByRole('tab', { name: 'Hoje' })).toHaveAttribute(
        'aria-selected',
        'true',
      );

      // One-time per device: reload auto-unlocks and never invites again.
      await page.reload();
      const reloadFlow = await waitForAppReady(page);
      expect(reloadFlow).toBe('none');
      await expect(page.getByText('Quem vai usar o app?')).toHaveCount(0);
    },
  );

  test('profile filled on the invitation is saved and shown in Perfil',
    async ({ page }) => {
      await bootToInvitation(page);

      // Fill the name and grant the LGPD consent. Flutter web merges label
      // + hint into the accessible name ("Nome Como você quer ser chamado"),
      // so match by prefix; fillFlutterField verifies the value stuck (the
      // native <input> is re-parented on focus swaps).
      const nome = page.getByRole('textbox', { name: /^Nome/ }).first();
      await fillFlutterField(page, nome, 'Ana Teste');
      // The consent CheckboxListTile exposes the long LGPD sentence as its
      // accessible name (no matching text node) — click by role. Match by
      // label: with allergy chips on the form the chips are ALSO exposed
      // as (disabled) role=checkbox and would win a bare .first().
      await page
        .getByRole('checkbox', { name: /Autorizo o tratamento/ })
        .first()
        .click();

      await page.getByRole('button', { name: 'Salvar e começar' }).click();

      // Bootstrap runs after the invitation: title + main shell.
      await expect
        .poll(() => page.title(), { timeout: 30000 })
        .toBe('Remédio na Hora');

      // The saved name is in the Perfil tab form.
      await page.getByRole('tab', { name: 'Perfil' }).click();
      await page.waitForTimeout(1000);
      const savedNome = page.getByRole('textbox', { name: /^Nome/ }).first();
      await savedNome.click();
      await expect(savedNome).toHaveValue('Ana Teste', { timeout: 10000 });
    },
  );

  test('allergy filled on the invitation persists across a reload', async ({
    page,
  }) => {
    await bootToInvitation(page);

    // Name (required) via the accessible textbox…
    const nome = page.getByRole('textbox', { name: /^Nome/ }).first();
    await fillFlutterField(page, nome, 'Ana Teste');

    // …and one allergy chip. The list-editor inputs carry no accessible
    // name (the InputDecorator label merges into a group), so click the
    // input by coordinates (1280x720 viewport) and submit with Enter
    // (onSubmitted adds the chip, same as the ⊕ button).
    await page.mouse.click(550, 528);
    await page.waitForTimeout(400);
    await page.keyboard.type('Dipirona', { delay: 40 });
    await page.waitForTimeout(300);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(400);

    // Consent + save (match by the LGPD label — allergy chips are also
    // exposed as role=checkbox and disabled).
    await page
      .getByRole('checkbox', { name: /Autorizo o tratamento/ })
      .first()
      .click();
    await page.getByRole('button', { name: 'Salvar e começar' }).click();
    await expect
      .poll(() => page.title(), { timeout: 30000 })
      .toBe('Remédio na Hora');

    // Reload: the vault auto-unlocks and the profile comes back from the
    // database — the allergy chip (InputChip exposes role=checkbox with the
    // chip text as its accessible name) and the emergency card row.
    await page.reload();
    const reloadFlow = await waitForAppReady(page);
    expect(reloadFlow).toBe('none');

    await page.getByRole('tab', { name: 'Perfil' }).click();
    await page.waitForTimeout(1500);
    await expect(
      page.getByRole('checkbox', { name: 'Dipirona' }).first(),
    ).toBeVisible({ timeout: 20000 });
    // The emergency card renders its title on canvas (no text node in the
    // semantics host) — assert via its share IconButton (tooltip = label).
    await expect(
      page.getByRole('button', { name: 'Compartilhar como imagem' }),
    ).toBeVisible({ timeout: 20000 });
  });
});
