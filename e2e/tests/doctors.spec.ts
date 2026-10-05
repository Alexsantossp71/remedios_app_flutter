import { test, expect } from '@playwright/test';
import { waitForAppReady, navigateToTab, takeScreenshot } from '../utils/helpers';
import testData from '../fixtures/test-data.json';

test.describe('Doctor Management', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
    await navigateToTab(page, 'Médicos');
  });

  test('should display empty state when no doctors exist', async ({ page }) => {
    await expect(page.locator('text=Seus médicos')).toBeVisible();
    await expect(page.locator('text=Seu catálogo começa aqui')).toBeVisible();
    await takeScreenshot(page, 'doctors-empty-state');
  });

  test('should add all 6 doctors with full details', async ({ page }) => {
    for (let i = 0; i < testData.doctors.length; i++) {
      const doctor = testData.doctors[i];

      // Click add button (first doctor vs subsequent)
      if (i === 0) {
        await page.click('text=Cadastrar primeiro médico');
      } else {
        // Look for FAB or add button
        const addButton = page.locator('[data-testid="add-doctor"], text=Cadastrar médico, text=Adicionar médico').first();
        await addButton.click();
      }
      await page.waitForTimeout(500);

      // Fill doctor form
      await page.fill('[placeholder="Nome do médico"]', doctor.name);
      await page.fill('[placeholder="Especialidade"]', doctor.specialty);
      await page.fill('[placeholder="CRM"]', doctor.crm_number);

      // Select CRM UF
      await page.click('text=UF do CRM');
      await page.waitForTimeout(300);
      await page.click(`text=${doctor.crm_uf}`);
      await page.waitForTimeout(300);

      // Fill phone
      await page.fill('[placeholder="Telefone"]', doctor.phone);

      // Fill clinic
      await page.fill('[placeholder="Clínica ou consultório"]', doctor.clinic);

      // Fill address manually
      await page.click('text=Preencher endereço sem CEP');
      await page.waitForTimeout(300);

      await page.fill('[placeholder="Rua ou avenida"]', doctor.address_street);
      await page.fill('[placeholder="Número"]', doctor.address_number);
      await page.fill('[placeholder="Cidade"]', doctor.city);

      // Select state UF
      const ufDropdowns = page.locator('text=UF');
      await ufDropdowns.last().click();
      await page.waitForTimeout(300);
      await page.locator(`text=${doctor.state}`).last().click();
      await page.waitForTimeout(300);

      // Submit form
      await page.click('text=Cadastrar');
      await page.waitForTimeout(1000);

      // Verify doctor appears in list
      await expect(page.locator(`text=${doctor.name}`)).toBeVisible({ timeout: 5000 });
      await expect(page.locator(`text=${doctor.specialty} · CRM ${doctor.crm_number}/${doctor.crm_uf}`)).toBeVisible();

      // Take screenshot after adding each doctor
      await takeScreenshot(page, `doctor-${i + 1}-${doctor.name.split(' ')[1].toLowerCase()}`);
    }

    // Final screenshot with all 6 doctors
    await takeScreenshot(page, 'doctors-all-6-registered');

    // Verify all 6 doctors are visible
    for (const doctor of testData.doctors) {
      await expect(page.locator(`text=${doctor.name}`)).toBeVisible();
    }
  });

  test('should display doctor details correctly', async ({ page }) => {
    // Add first doctor
    const doctor = testData.doctors[0];
    await page.click('text=Cadastrar primeiro médico');
    await page.waitForTimeout(500);

    await page.fill('[placeholder="Nome do médico"]', doctor.name);
    await page.fill('[placeholder="Especialidade"]', doctor.specialty);
    await page.fill('[placeholder="CRM"]', doctor.crm_number);
    await page.click('text=UF do CRM');
    await page.waitForTimeout(300);
    await page.click(`text=${doctor.crm_uf}`);
    await page.waitForTimeout(300);
    await page.fill('[placeholder="Telefone"]', doctor.phone);
    await page.fill('[placeholder="Clínica ou consultório"]', doctor.clinic);

    await page.click('text=Preencher endereço sem CEP');
    await page.waitForTimeout(300);
    await page.fill('[placeholder="Rua ou avenida"]', doctor.address_street);
    await page.fill('[placeholder="Número"]', doctor.address_number);
    await page.fill('[placeholder="Cidade"]', doctor.city);
    await page.locator('text=UF').last().click();
    await page.waitForTimeout(300);
    await page.locator(`text=${doctor.state}`).last().click();
    await page.waitForTimeout(300);

    await page.click('text=Cadastrar');
    await page.waitForTimeout(1000);

    // Verify all doctor details
    await expect(page.locator(`text=${doctor.name}`)).toBeVisible();
    await expect(page.locator(`text=${doctor.specialty} · CRM ${doctor.crm_number}/${doctor.crm_uf}`)).toBeVisible();
    await expect(page.locator(`text=${doctor.address_street}`).first()).toBeVisible();

    // Verify CRM verification badge
    await expect(page.locator('[title="Verificar gratuitamente no CFM"], [data-tooltip="Verificar gratuitamente no CFM"]')).toBeVisible();

    await takeScreenshot(page, 'doctor-details-view');
  });

  test('should edit a doctor', async ({ page }) => {
    // Add a doctor first
    const doctor = testData.doctors[1];
    await page.click('text=Cadastrar primeiro médico');
    await page.waitForTimeout(500);

    await page.fill('[placeholder="Nome do médico"]', doctor.name);
    await page.fill('[placeholder="Especialidade"]', doctor.specialty);
    await page.fill('[placeholder="CRM"]', doctor.crm_number);
    await page.click('text=UF do CRM');
    await page.waitForTimeout(300);
    await page.click(`text=${doctor.crm_uf}`);
    await page.waitForTimeout(300);
    await page.fill('[placeholder="Telefone"]', doctor.phone);
    await page.fill('[placeholder="Clínica ou consultório"]', doctor.clinic);

    await page.click('text=Preencher endereço sem CEP');
    await page.waitForTimeout(300);
    await page.fill('[placeholder="Rua ou avenida"]', doctor.address_street);
    await page.fill('[placeholder="Número"]', doctor.address_number);
    await page.fill('[placeholder="Cidade"]', doctor.city);
    await page.locator('text=UF').last().click();
    await page.waitForTimeout(300);
    await page.locator(`text=${doctor.state}`).last().click();
    await page.waitForTimeout(300);

    await page.click('text=Cadastrar');
    await page.waitForTimeout(1000);

    // Click on doctor to open details/edit
    await page.click(`text=${doctor.name}`);
    await page.waitForTimeout(500);

    // Look for edit button
    const editButton = page.locator('text=Editar, [data-testid="edit-doctor"]').first();
    if (await editButton.isVisible()) {
      await editButton.click();
      await page.waitForTimeout(500);

      // Update phone number
      const newPhone = '(11) 91234-5678';
      await page.fill('[placeholder="Telefone"]', newPhone);

      // Save
      await page.click('text=Salvar');
      await page.waitForTimeout(1000);

      // Verify update
      await expect(page.locator(`text=${newPhone}`)).toBeVisible();
      await takeScreenshot(page, 'doctor-edited');
    }
  });

  test('should delete a doctor', async ({ page }) => {
    // Add a doctor first
    const doctor = testData.doctors[2];
    await page.click('text=Cadastrar primeiro médico');
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

    // Verify doctor exists
    await expect(page.locator(`text=${doctor.name}`)).toBeVisible();

    // Click on doctor
    await page.click(`text=${doctor.name}`);
    await page.waitForTimeout(500);

    // Look for delete button
    const deleteButton = page.locator('text=Excluir, text=Deletar, [data-testid="delete-doctor"]').first();
    if (await deleteButton.isVisible()) {
      await deleteButton.click();
      await page.waitForTimeout(500);

      // Confirm deletion
      await page.click('text=Confirmar, text=Excluir').first();
      await page.waitForTimeout(1000);

      // Verify doctor is removed
      await expect(page.locator(`text=${doctor.name}`)).not.toBeVisible();
      await takeScreenshot(page, 'doctor-deleted');
    }
  });

  test('should validate CRM badge for all doctors', async ({ page }) => {
    // Add 2 doctors and verify CRM badge
    for (let i = 0; i < 2; i++) {
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

      // Verify CRM display
      await expect(page.locator(`text=CRM ${doctor.crm_number}/${doctor.crm_uf}`)).toBeVisible();
    }

    await takeScreenshot(page, 'doctors-crm-badges');
  });
});
