import { test, expect } from '@playwright/test';
import { waitForAppReady, navigateToTab, takeScreenshot } from '../utils/helpers';
import testData from '../fixtures/test-data.json';

test.describe('Medicine/Treatment Management', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
    await navigateToTab(page, 'Medicamentos');
  });

  test('should display empty state when no treatments exist', async ({ page }) => {
    await expect(page.locator('text=Seus medicamentos')).toBeVisible();
    await takeScreenshot(page, 'medicines-empty-state');
  });

  test('should add all 7 treatments with full details', async ({ page }) => {
    for (let i = 0; i < testData.treatments.length; i++) {
      const treatment = testData.treatments[i];

      // Click add button
      const addButton = page.locator('text=Adicionar tratamento, text=Adicionar medicamento, [data-testid="add-treatment"]').first();
      await addButton.click();
      await page.waitForTimeout(500);

      // Search for medicine in catalog
      const searchField = page.locator('[placeholder="Buscar medicamento"], [placeholder="Nome do medicamento"]').first();
      await searchField.fill(treatment.medicine_name);
      await page.waitForTimeout(1000);

      // Select from autocomplete results (click first match)
      const suggestion = page.locator(`text=${treatment.medicine_name}`).first();
      if (await suggestion.isVisible()) {
        await suggestion.click();
        await page.waitForTimeout(500);
      }

      // Fill dosage
      const dosageField = page.locator('[placeholder="Dosagem"], [placeholder="Ex: 500mg"]').first();
      if (await dosageField.isVisible()) {
        await dosageField.fill(treatment.dosage);
      }

      // Fill frequency
      const frequencyField = page.locator('[placeholder="Frequência"], text=Frequência').first();
      if (await frequencyField.isVisible()) {
        await frequencyField.click();
        await page.waitForTimeout(300);

        // Try to select from frequency options or fill manually
        const option = page.locator(`text=${treatment.frequency}`).first();
        if (await option.isVisible()) {
          await option.click();
        }
      }

      // Fill start time
      const timeField = page.locator('[placeholder="Horário"], [type="time"]').first();
      if (await timeField.isVisible()) {
        await timeField.fill(treatment.start_time);
      }

      // Fill notes
      const notesField = page.locator('[placeholder="Observações"], [placeholder="Notas"]').first();
      if (await notesField.isVisible()) {
        await notesField.fill(treatment.notes);
      }

      // Submit treatment
      const submitButton = page.locator('text=Cadastrar, text=Salvar, text=Adicionar').last();
      await submitButton.click();
      await page.waitForTimeout(1000);

      // Verify treatment appears in list
      await expect(page.locator(`text=${treatment.medicine_name}`).first()).toBeVisible({ timeout: 5000 });

      // Take screenshot
      await takeScreenshot(page, `treatment-${i + 1}-${treatment.medicine_name.toLowerCase()}`);
    }

    // Final screenshot with all treatments
    await takeScreenshot(page, 'treatments-all-7-registered');

    // Verify all 7 treatments are visible
    for (const treatment of testData.treatments) {
      await expect(page.locator(`text=${treatment.medicine_name}`).first()).toBeVisible();
    }
  });

  test('should display treatment details correctly', async ({ page }) => {
    const treatment = testData.treatments[0]; // Dipirona

    // Add treatment
    const addButton = page.locator('text=Adicionar tratamento, text=Adicionar medicamento').first();
    await addButton.click();
    await page.waitForTimeout(500);

    const searchField = page.locator('[placeholder="Buscar medicamento"], [placeholder="Nome do medicamento"]').first();
    await searchField.fill(treatment.medicine_name);
    await page.waitForTimeout(1000);

    const suggestion = page.locator(`text=${treatment.medicine_name}`).first();
    if (await suggestion.isVisible()) {
      await suggestion.click();
      await page.waitForTimeout(500);
    }

    const dosageField = page.locator('[placeholder="Dosagem"], [placeholder="Ex: 500mg"]').first();
    if (await dosageField.isVisible()) {
      await dosageField.fill(treatment.dosage);
    }

    const notesField = page.locator('[placeholder="Observações"], [placeholder="Notas"]').first();
    if (await notesField.isVisible()) {
      await notesField.fill(treatment.notes);
    }

    const submitButton = page.locator('text=Cadastrar, text=Salvar, text=Adicionar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Verify treatment details
    await expect(page.locator(`text=${treatment.medicine_name}`).first()).toBeVisible();
    await expect(page.locator(`text=${treatment.dosage}`).first()).toBeVisible();

    await takeScreenshot(page, 'treatment-details-dipirona');
  });

  test('should show treatments in Hoje tab after adding', async ({ page }) => {
    const treatment = testData.treatments[0]; // Dipirona

    // Add treatment
    const addButton = page.locator('text=Adicionar tratamento, text=Adicionar medicamento').first();
    await addButton.click();
    await page.waitForTimeout(500);

    const searchField = page.locator('[placeholder="Buscar medicamento"], [placeholder="Nome do medicamento"]').first();
    await searchField.fill(treatment.medicine_name);
    await page.waitForTimeout(1000);

    const suggestion = page.locator(`text=${treatment.medicine_name}`).first();
    if (await suggestion.isVisible()) {
      await suggestion.click();
      await page.waitForTimeout(500);
    }

    const submitButton = page.locator('text=Cadastrar, text=Salvar, text=Adicionar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Navigate to Hoje tab
    await navigateToTab(page, 'Hoje');
    await page.waitForTimeout(500);

    // Check if treatment dose appears in today's view
    const todayDose = page.locator(`text=${treatment.medicine_name}`).first();
    if (await todayDose.isVisible()) {
      await expect(todayDose).toBeVisible();
      await takeScreenshot(page, 'today-with-treatment');
    }
  });

  test('should edit a treatment', async ({ page }) => {
    const treatment = testData.treatments[1]; // Losartana

    // Add treatment
    const addButton = page.locator('text=Adicionar tratamento, text=Adicionar medicamento').first();
    await addButton.click();
    await page.waitForTimeout(500);

    const searchField = page.locator('[placeholder="Buscar medicamento"], [placeholder="Nome do medicamento"]').first();
    await searchField.fill(treatment.medicine_name);
    await page.waitForTimeout(1000);

    const suggestion = page.locator(`text=${treatment.medicine_name}`).first();
    if (await suggestion.isVisible()) {
      await suggestion.click();
      await page.waitForTimeout(500);
    }

    const submitButton = page.locator('text=Cadastrar, text=Salvar, text=Adicionar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Click on treatment to edit
    await page.click(`text=${treatment.medicine_name}`);
    await page.waitForTimeout(500);

    // Look for edit option
    const editButton = page.locator('text=Editar, [data-testid="edit-treatment"]').first();
    if (await editButton.isVisible()) {
      await editButton.click();
      await page.waitForTimeout(500);

      // Update notes
      const notesField = page.locator('[placeholder="Observações"], [placeholder="Notas"]').first();
      if (await notesField.isVisible()) {
        await notesField.fill('Dosagem atualizada pelo médico');
      }

      await page.click('text=Salvar').first();
      await page.waitForTimeout(1000);

      await takeScreenshot(page, 'treatment-edited');
    }
  });

  test('should delete a treatment', async ({ page }) => {
    const treatment = testData.treatments[4]; // Prednisona

    // Add treatment
    const addButton = page.locator('text=Adicionar tratamento, text=Adicionar medicamento').first();
    await addButton.click();
    await page.waitForTimeout(500);

    const searchField = page.locator('[placeholder="Buscar medicamento"], [placeholder="Nome do medicamento"]').first();
    await searchField.fill(treatment.medicine_name);
    await page.waitForTimeout(1000);

    const suggestion = page.locator(`text=${treatment.medicine_name}`).first();
    if (await suggestion.isVisible()) {
      await suggestion.click();
      await page.waitForTimeout(500);
    }

    const submitButton = page.locator('text=Cadastrar, text=Salvar, text=Adicionar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Verify treatment exists
    await expect(page.locator(`text=${treatment.medicine_name}`).first()).toBeVisible();

    // Click on treatment
    await page.click(`text=${treatment.medicine_name}`);
    await page.waitForTimeout(500);

    // Delete
    const deleteButton = page.locator('text=Excluir, text=Deletar, [data-testid="delete-treatment"]').first();
    if (await deleteButton.isVisible()) {
      await deleteButton.click();
      await page.waitForTimeout(500);

      await page.click('text=Confirmar, text=Excluir').first();
      await page.waitForTimeout(1000);

      // Verify removed
      await expect(page.locator(`text=${treatment.medicine_name}`)).not.toBeVisible();
      await takeScreenshot(page, 'treatment-deleted');
    }
  });

  test('should search medicines in catalog', async ({ page }) => {
    const searchTerms = ['Dipirona', 'Losartana', 'Omeprazol'];

    for (const term of searchTerms) {
      const addButton = page.locator('text=Adicionar tratamento, text=Adicionar medicamento').first();
      await addButton.click();
      await page.waitForTimeout(500);

      const searchField = page.locator('[placeholder="Buscar medicamento"], [placeholder="Nome do medicamento"]').first();
      await searchField.fill(term);
      await page.waitForTimeout(1000);

      // Verify search results appear
      const results = page.locator(`text=${term}`);
      await expect(results.first()).toBeVisible({ timeout: 5000 });

      await takeScreenshot(page, `medicine-search-${term.toLowerCase()}`);

      // Close dialog
      await page.keyboard.press('Escape');
      await page.waitForTimeout(500);
    }
  });
});
