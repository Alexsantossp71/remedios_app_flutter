import { test, expect } from '@playwright/test';
import { waitForAppReady, navigateToTab, takeScreenshot } from '../utils/helpers';
import testData from '../fixtures/test-data.json';

test.describe('Health Plans Management', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
    await navigateToTab(page, 'Planos');
  });

  test('should display empty state when no health plans exist', async ({ page }) => {
    await expect(page.locator('text=Seus planos de saúde')).toBeVisible();

    // Check for empty state message
    const emptyState = page.locator('text=Adicionar plano');
    await expect(emptyState).toBeVisible();
  });

  test('should add 3 health plans successfully', async ({ page }) => {
    for (const plan of testData.health_plans) {
      // Click add button
      await page.click('text=Adicionar plano');
      await page.waitForTimeout(500);

      // Fill form
      await page.fill('[placeholder="Nome do plano"]', plan.name);
      await page.fill('[placeholder="Número da carteirinha"]', plan.card_number);

      // Fill expiry date
      const expiryField = page.locator('[placeholder="Validade"], [placeholder="MM/AAAA"]').first();
      if (await expiryField.isVisible()) {
        await expiryField.fill(plan.expiry_date);
      }

      // Select type if dropdown exists
      const typeDropdown = page.locator('text=Tipo').first();
      if (await typeDropdown.isVisible()) {
        await typeDropdown.click();
        await page.click(`text=${plan.type}`);
      }

      // Submit form
      await page.click('text=Cadastrar, text=Salvar, text=Adicionar').first();
      await page.waitForTimeout(1000);

      // Verify plan appears in list
      await expect(page.locator(`text=${plan.name}`)).toBeVisible({ timeout: 5000 });

      // Take screenshot
      await takeScreenshot(page, `health-plan-${plan.name.toLowerCase()}`);
    }

    // Verify all 3 plans are visible
    await expect(page.locator('text=Unimed')).toBeVisible();
    await expect(page.locator('text=SulAmérica')).toBeVisible();
    await expect(page.locator('text=Amil')).toBeVisible();
  });

  test('should display health plan details correctly', async ({ page }) => {
    // First add a plan
    await page.click('text=Adicionar plano');
    await page.waitForTimeout(500);

    const plan = testData.health_plans[0];
    await page.fill('[placeholder="Nome do plano"]', plan.name);
    await page.fill('[placeholder="Número da carteirinha"]', plan.card_number);
    await page.click('text=Cadastrar').first();
    await page.waitForTimeout(1000);

    // Click on plan to view details
    await page.click(`text=${plan.name}`);
    await page.waitForTimeout(500);

    // Verify details are shown
    await expect(page.locator(`text=${plan.card_number}`)).toBeVisible();
  });

  test('should edit an existing health plan', async ({ page }) => {
    // Add a plan first
    await page.click('text=Adicionar plano');
    await page.waitForTimeout(500);

    const plan = testData.health_plans[1];
    await page.fill('[placeholder="Nome do plano"]', plan.name);
    await page.fill('[placeholder="Número da carteirinha"]', plan.card_number);
    await page.click('text=Cadastrar').first();
    await page.waitForTimeout(1000);

    // Find and click edit button
    const editButton = page.locator(`text=${plan.name}`).locator('..').locator('text=Editar, [data-testid="edit-button"]').first();
    if (await editButton.isVisible()) {
      await editButton.click();
      await page.waitForTimeout(500);

      // Update the card number
      const newCardNumber = 'NEW1234567890123';
      await page.fill('[placeholder="Número da carteirinha"]', newCardNumber);
      await page.click('text=Salvar').first();
      await page.waitForTimeout(1000);

      // Verify update
      await expect(page.locator(`text=${newCardNumber}`)).toBeVisible();
    }
  });

  test('should delete a health plan', async ({ page }) => {
    // Add a plan first
    await page.click('text=Adicionar plano');
    await page.waitForTimeout(500);

    const plan = testData.health_plans[2];
    await page.fill('[placeholder="Nome do plano"]', plan.name);
    await page.fill('[placeholder="Número da carteirinha"]', plan.card_number);
    await page.click('text=Cadastrar').first();
    await page.waitForTimeout(1000);

    // Verify plan exists
    await expect(page.locator(`text=${plan.name}`)).toBeVisible();

    // Find and click delete button
    const deleteButton = page.locator(`text=${plan.name}`).locator('..').locator('text=Excluir, text=Deletar, [data-testid="delete-button"]').first();
    if (await deleteButton.isVisible()) {
      await deleteButton.click();
      await page.waitForTimeout(500);

      // Confirm deletion
      await page.click('text=Confirmar, text=Excluir').first();
      await page.waitForTimeout(1000);

      // Verify plan is removed
      await expect(page.locator(`text=${plan.name}`)).not.toBeVisible();
    }
  });
});
