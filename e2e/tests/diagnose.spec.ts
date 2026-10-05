import { test, expect } from '@playwright/test';

test.describe('Diagnostic: Flutter Web Rendering', () => {
  test('capture what the app actually renders', async ({ page }) => {
    console.log('=== DIAGNOSTIC: Flutter Web App ===\n');
    console.log('1. Navigating to http://localhost:5000/...');

    await page.goto('http://localhost:5000/', {
      waitUntil: 'domcontentloaded',
      timeout: 60000
    });
    console.log('   ✅ Page loaded (domcontentloaded)\n');

    // Wait for Flutter engine to potentially load
    console.log('2. Waiting 20 seconds for Flutter to initialize...');
    await page.waitForTimeout(20000);
    console.log('   Done\n');

    // Check page title
    const title = await page.title();
    console.log(`3. Page title: "${title}"\n`);

    // Check URL
    const url = page.url();
    console.log(`4. Current URL: ${url}\n`);

    // Check body inner text
    const bodyText = await page.evaluate(() => document.body?.innerText || '(empty)');
    console.log(`5. Body innerText (first 500 chars):\n   "${bodyText.substring(0, 500)}"\n`);

    // Check body innerHTML length
    const htmlLen = await page.evaluate(() => document.body?.innerHTML?.length || 0);
    console.log(`6. Body innerHTML length: ${htmlLen} chars\n`);

    // Check for Flutter-specific elements
    const flutterChecks = await page.evaluate(() => {
      const checks: Record<string, any> = {};

      // Check for Flutter engine
      checks['window._flutter'] = typeof (window as any)._flutter;
      checks['window._flutter value'] = (window as any)._flutter != null ? 'exists' : 'null/undefined';

      // Check for Flutter view
      const flutterView = document.querySelector('flutter-view');
      checks['flutter-view element'] = flutterView ? 'found' : 'not found';

      // Check for flt-glass-pane (older Flutter web)
      const glassPane = document.querySelector('flt-glass-pane');
      checks['flt-glass-pane element'] = glassPane ? 'found' : 'not found';

      // Check for canvas elements
      const canvases = document.querySelectorAll('canvas');
      checks['canvas count'] = canvases.length;

      // Check for shadow DOM
      const shadowHosts = document.querySelectorAll('*');
      let shadowCount = 0;
      shadowHosts.forEach(el => { if (el.shadowRoot) shadowCount++; });
      checks['elements with shadowRoot'] = shadowCount;

      // Check for flt-semantics elements (Flutter accessibility tree)
      const semantics = document.querySelectorAll('flt-semantics');
      checks['flt-semantics count'] = semantics.length;

      const semanticsContainer = document.querySelector('flt-semantics-container');
      checks['flt-semantics-container'] = semanticsContainer ? 'found' : 'not found';

      // Check all flt-* elements
      const fltElements = document.querySelectorAll('[id^="flt-"], flt-semantics, flt-semantics-container, flt-semantics-host, flutter-view, flt-glass-pane, flt-scene-host, flt-scene');
      checks['flt-* elements count'] = fltElements.length;
      const fltTypes = new Set<string>();
      fltElements.forEach(el => fltTypes.add(el.tagName.toLowerCase()));
      checks['flt-* element types'] = Array.from(fltTypes).join(', ') || 'none';

      // Check for aria labels
      const ariaElements = document.querySelectorAll('[aria-label]');
      const ariaLabels: string[] = [];
      ariaElements.forEach(el => {
        const label = el.getAttribute('aria-label');
        if (label) ariaLabels.push(label);
      });
      checks['aria-label count'] = ariaLabels.length;
      checks['aria-labels (first 20)'] = ariaLabels.slice(0, 20).join(' | ') || 'none';

      // Check for role attributes
      const roleElements = document.querySelectorAll('[role]');
      const roles: string[] = [];
      roleElements.forEach(el => {
        const role = el.getAttribute('role');
        const label = el.getAttribute('aria-label') || el.textContent?.substring(0, 30) || '';
        if (role) roles.push(`${role}:${label}`);
      });
      checks['role count'] = roles.length;
      checks['roles (first 20)'] = roles.slice(0, 20).join(' | ') || 'none';

      // HTML structure overview
      const bodyChildren = Array.from(document.body.children).map(c =>
        `${c.tagName.toLowerCase()}${c.id ? '#'+c.id : ''}${c.className ? '.'+c.className.split(' ')[0] : ''}`
      );
      checks['body children'] = bodyChildren.join(', ') || 'none';

      return checks;
    });

    console.log('7. Flutter-specific checks:');
    for (const [key, value] of Object.entries(flutterChecks)) {
      console.log(`   ${key}: ${value}`);
    }
    console.log('');

    // Take a screenshot
    await page.screenshot({ path: 'fixtures/screenshots/diagnostic-page.png', fullPage: true });
    console.log('8. Screenshot saved: fixtures/screenshots/diagnostic-page.png\n');

    // Try to find text in shadow DOM
    const shadowTexts = await page.evaluate(() => {
      const texts: string[] = [];
      const walkShadow = (root: Document | ShadowRoot, depth: number) => {
        if (depth > 5) return;
        root.querySelectorAll('*').forEach(el => {
          if (el.shadowRoot) {
            walkShadow(el.shadowRoot, depth + 1);
          }
          // Check for text content in semantic nodes
          if (el.textContent && el.children.length === 0) {
            const t = el.textContent.trim();
            if (t.length > 0 && t.length < 200) {
              texts.push(`[${el.tagName}] ${t}`);
            }
          }
        });
      };
      walkShadow(document, 0);
      return texts.slice(0, 50);
    });

    console.log('9. Text content found (including shadow DOM, first 50):');
    if (shadowTexts.length === 0) {
      console.log('   (none found)');
    } else {
      shadowTexts.forEach(t => console.log(`   ${t}`));
    }
    console.log('');

    // Check if Flutter uses CanvasKit or HTML renderer
    const renderer = await page.evaluate(() => {
      // Check for CanvasKit indicators
      const hasCanvasKit = document.querySelector('canvas') != null;
      const hasHtmlRenderer = document.querySelector('flt-paragraph') != null ||
                              document.querySelector('flt-span') != null;
      if (hasHtmlRenderer) return 'HTML renderer';
      if (hasCanvasKit) return 'CanvasKit (canvas-based)';
      return 'Unknown';
    });
    console.log(`10. Flutter renderer: ${renderer}\n`);

    // Try enabling semantics
    console.log('11. Attempting to enable Flutter semantics...');
    await page.evaluate(() => {
      // Flutter semantics can be enabled by dispatching a specific event
      (window as any)._flutter?.loader?.loadEntrypoint?.({
        onEntrypointLoaded: () => {}
      });
    });
    await page.waitForTimeout(2000);

    // Check semantics again after enable attempt
    const afterSemantics = await page.evaluate(() => {
      const semantics = document.querySelectorAll('flt-semantics, [role], [aria-label]');
      const items: string[] = [];
      semantics.forEach(el => {
        const tag = el.tagName.toLowerCase();
        const role = el.getAttribute('role') || '';
        const label = el.getAttribute('aria-label') || '';
        const text = el.textContent?.substring(0, 50) || '';
        items.push(`${tag} role="${role}" aria="${label}" text="${text}"`);
      });
      return items.slice(0, 30);
    });
    console.log(`   Found ${afterSemantics.length} semantic elements:`);
    afterSemantics.forEach(s => console.log(`   ${s}`));
    console.log('');

    // Try to enable semantics via SemanticsBinding
    console.log('12. Trying to enable accessibility/semantics via keyboard shortcut...');
    // Pressing Tab usually triggers Flutter to enable semantics
    await page.keyboard.press('Tab');
    await page.waitForTimeout(3000);

    const finalSemantics = await page.evaluate(() => {
      const all = document.querySelectorAll('[role], [aria-label], flt-semantics');
      const items: string[] = [];
      all.forEach(el => {
        const tag = el.tagName.toLowerCase();
        const role = el.getAttribute('role') || '';
        const label = el.getAttribute('aria-label') || '';
        items.push(`${tag} role="${role}" aria-label="${label}"`);
      });
      return { count: items.length, items: items.slice(0, 30) };
    });
    console.log(`   After Tab press: ${finalSemantics.count} semantic elements`);
    finalSemantics.items.forEach(s => console.log(`   ${s}`));

    console.log('\n=== DIAGNOSTICS COMPLETE ===');
  });
});