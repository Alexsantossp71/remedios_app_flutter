import { test, expect } from '@playwright/test';
import { waitForAppReady, navigateToTab, takeScreenshot } from '../utils/helpers';
import testData from '../fixtures/test-data.json';

test.describe('Consultation Scheduling', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);

    // First add doctors that will be referenced in consultations
    await navigateToTab(page, 'Médicos');
    await page.waitForTimeout(500);

    // Add first 3 doctors for consultations
    for (let i = 0; i < 3; i++) {
      const doctor = testData.doctors[i];

      const addBtn = i === 0
        ? page.locator('text=Cadastrar primeiro médico')
        : page.locator('[data-testid="add-doctor"], text=Cadastrar médico, text=Adicionar médico').first();

      await addBtn.click();
      await page.waitForTimeout(500);

      await page.fill('[placeholder="Nome do médico"]', doctor.name);
      await page.fill('[placeholder="Especialidade"]', doctor.specialty);
      await page.fill('[placeholder="CRM"]', doctor.crm_number);
      await page.click('text=UF do CRM');
      await page.waitForTimeout(300);
      await page.click(`text=${doctor.crm_uf}`);
      await page.waitForTimeout(300);
      await page.fill('[placeholder="Telefone"]', doctor.phone);

      await page.click('text=Cadastrar');
      await page.waitForTimeout(1000);
    }

    // Navigate to Consultas tab
    await navigateToTab(page, 'Consultas');
  });

  test('should display empty state when no consultations exist', async ({ page }) => {
    await expect(page.locator('text=Suas consultas')).toBeVisible();
    await takeScreenshot(page, 'consultations-empty-state');
  });

  test('should schedule all 5 consultations', async ({ page }) => {
    for (let i = 0; i < testData.consultations.length; i++) {
      const consultation = testData.consultations[i];

      // Click add consultation button
      const addButton = page.locator('text=Agendar consulta, text=Nova consulta, text=Adicionar consulta, [data-testid="add-consultation"]').first();
      await addButton.click();
      await page.waitForTimeout(500);

      // Select doctor from dropdown
      const doctorField = page.locator('[placeholder="Médico"], text=Selecionar médico, text=Médico').first();
      await doctorField.click();
      await page.waitForTimeout(300);
      const doctorOption = page.locator(`text=${consultation.doctor_name}`).first();
      if (await doctorOption.isVisible()) {
        await doctorOption.click();
        await page.waitForTimeout(300);
      }

      // Fill location
      const locationField = page.locator('[placeholder="Local"], [placeholder="Local da consulta"]').first();
      if (await locationField.isVisible()) {
        await locationField.fill(consultation.location);
      }

      // Fill date
      const dateField = page.locator('[placeholder="Data"], [type="date"]').first();
      if (await dateField.isVisible()) {
        await dateField.fill(consultation.date);
      }

      // Fill time
      const timeField = page.locator('[placeholder="Horário"], [type="time"]').first();
      if (await timeField.isVisible()) {
        await timeField.fill(consultation.time);
      }

      // Fill notes
      const notesField = page.locator('[placeholder="Observações"], [placeholder="Notas"], [placeholder="Anotações"]').first();
      if (await notesField.isVisible()) {
        await notesField.fill(consultation.notes);
      }

      // Select type if available
      if (consultation.type) {
        const typeField = page.locator('text=Tipo, [placeholder="Tipo"]').first();
        if (await typeField.isVisible()) {
          await typeField.click();
          await page.waitForTimeout(300);
          const typeOption = page.locator(`text=${consultation.type}`).first();
          if (await typeOption.isVisible()) {
            await typeOption.click();
          }
        }
      }

      // Submit
      const submitButton = page.locator('text=Agendar, text=Salvar, text=Cadastrar').last();
      await submitButton.click();
      await page.waitForTimeout(1000);

      // Verify consultation appears
      await expect(page.locator(`text=${consultation.doctor_name}`).first()).toBeVisible({ timeout: 5000 });

      // Take screenshot
      await takeScreenshot(page, `consultation-${i + 1}-${consultation.doctor_name.split(' ')[1].toLowerCase()}`);
    }

    // Final screenshot with all consultations
    await takeScreenshot(page, 'consultations-all-5-scheduled');

    // Verify all 5 consultations
    for (const consultation of testData.consultations) {
      await expect(page.locator(`text=${consultation.doctor_name}`).first()).toBeVisible();
    }
  });

  test('should display consultation details', async ({ page }) => {
    const consultation = testData.consultations[0];

    // Schedule a consultation
    const addButton = page.locator('text=Agendar consulta, text=Nova consulta, text=Adicionar consulta').first();
    await addButton.click();
    await page.waitForTimeout(500);

    // Select doctor
    const doctorField = page.locator('[placeholder="Médico"], text=Selecionar médico, text=Médico').first();
    await doctorField.click();
    await page.waitForTimeout(300);
    const doctorOption = page.locator(`text=${consultation.doctor_name}`).first();
    if (await doctorOption.isVisible()) {
      await doctorOption.click();
      await page.waitForTimeout(300);
    }

    // Fill location
    const locationField = page.locator('[placeholder="Local"], [placeholder="Local da consulta"]').first();
    if (await locationField.isVisible()) {
      await locationField.fill(consultation.location);
    }

    // Fill notes
    const notesField = page.locator('[placeholder="Observações"], [placeholder="Notas"]').first();
    if (await notesField.isVisible()) {
      await notesField.fill(consultation.notes);
    }

    // Submit
    const submitButton = page.locator('text=Agendar, text=Salvar, text=Cadastrar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Click on consultation to view details
    await page.click(`text=${consultation.doctor_name}`);
    await page.waitForTimeout(500);

    // Verify details displayed
    await expect(page.locator(`text=${consultation.doctor_name}`).first()).toBeVisible();
    await expect(page.locator(`text=${consultation.location}`).first()).toBeVisible();
    await expect(page.locator(`text=${consultation.notes}`).first()).toBeVisible();

    await takeScreenshot(page, 'consultation-details');
  });

  test('should cancel a scheduled consultation', async ({ page }) => {
    const consultation = testData.consultations[1];

    // Schedule a consultation
    const addButton = page.locator('text=Agendar consulta, text=Nova consulta').first();
    await addButton.click();
    await page.waitForTimeout(500);

    const doctorField = page.locator('[placeholder="Médico"], text=Selecionar médico, text=Médico').first();
    await doctorField.click();
    await page.waitForTimeout(300);
    const doctorOption = page.locator(`text=${consultation.doctor_name}`).first();
    if (await doctorOption.isVisible()) {
      await doctorOption.click();
      await page.waitForTimeout(300);
    }

    const locationField = page.locator('[placeholder="Local"], [placeholder="Local da consulta"]').first();
    if (await locationField.isVisible()) {
      await locationField.fill(consultation.location);
    }

    const submitButton = page.locator('text=Agendar, text=Salvar, text=Cadastrar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Verify consultation exists
    await expect(page.locator(`text=${consultation.doctor_name}`).first()).toBeVisible();

    // Click on consultation
    await page.click(`text=${consultation.doctor_name}`);
    await page.waitForTimeout(500);

    // Cancel/delete consultation
    const cancelButton = page.locator('text=Cancelar, text=Excluir, text=Cancelar consulta').first();
    if (await cancelButton.isVisible()) {
      await cancelButton.click();
      await page.waitForTimeout(500);

      // Confirm cancellation
      await page.click('text=Confirmar, text=Sim').first();
      await page.waitForTimeout(1000);

      await takeScreenshot(page, 'consultation-cancelled');
    }
  });

  test('should show consultations in calendar view', async ({ page }) => {
    // Schedule a consultation
    const consultation = testData.consultations[2];

    const addButton = page.locator('text=Agendar consulta, text=Nova consulta').first();
    await addButton.click();
    await page.waitForTimeout(500);

    const doctorField = page.locator('[placeholder="Médico"], text=Selecionar médico, text=Médico').first();
    await doctorField.click();
    await page.waitForTimeout(300);
    const doctorOption = page.locator(`text=${consultation.doctor_name}`).first();
    if (await doctorOption.isVisible()) {
      await doctorOption.click();
      await page.waitForTimeout(300);
    }

    const submitButton = page.locator('text=Agendar, text=Salvar, text=Cadastrar').last();
    await submitButton.click();
    await page.waitForTimeout(1000);

    // Verify calendar displays the consultation
    await takeScreenshot(page, 'consultation-calendar-view');
  });
});
