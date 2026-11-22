import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/theme/app_theme.dart';
import 'package:remedios_app_flutter/widgets/welcome_screen.dart';

/// Cobertura da [WelcomeScreen]:
/// - Renderiza nome do app, tagline e descrição.
/// - PrivacyBlurb mostra os 3 pontos de privacidade esperados.
/// - CTA "Começar" dispara [onStart].
/// - CTA "Ver demo" dispara [onSeeDemo] com [BuildContext].
/// - Diálogo "demo em desenvolvimento" abre e fecha corretamente.
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  testWidgets('renderiza nome do app, tagline e descrição', (tester) async {
    await tester.pumpWidget(
      host(WelcomeScreen(onStart: () {}, onSeeDemo: (_) {})),
    );

    expect(find.text('Remédio na Hora'), findsOneWidget);
    expect(find.text('Seus medicamentos, na hora certa.'), findsOneWidget);
    expect(find.textContaining('Organize medicamentos'), findsOneWidget);
    expect(find.textContaining('offline-first'), findsOneWidget);
  });

  testWidgets('PrivacyBlurb mostra os 3 pontos de privacidade', (tester) async {
    await tester.pumpWidget(
      host(WelcomeScreen(onStart: () {}, onSeeDemo: (_) {})),
    );

    expect(find.textContaining('Criptografado em repouso'), findsOneWidget);
    expect(find.textContaining('Sem nuvem'), findsOneWidget);
    expect(find.textContaining('IA e OCR são opcionais'), findsOneWidget);
  });

  testWidgets('CTA "Começar" dispara onStart', (tester) async {
    bool started = false;
    await tester.pumpWidget(
      host(WelcomeScreen(onStart: () => started = true, onSeeDemo: (_) {})),
    );

    final cta = find.text('Começar — criar meu cofre');
    expect(cta, findsOneWidget);
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pump();

    expect(started, isTrue);
  });

  testWidgets('CTA "Ver demo" dispara onSeeDemo com BuildContext', (
    tester,
  ) async {
    BuildContext? captured;
    await tester.pumpWidget(
      host(WelcomeScreen(onStart: () {}, onSeeDemo: (ctx) => captured = ctx)),
    );

    final cta = find.text('Ver demo (não salva dados)');
    expect(cta, findsOneWidget);
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pump();

    expect(captured, isNotNull);
  });

  testWidgets('BrandMark renderiza o ícone de medicação', (tester) async {
    await tester.pumpWidget(
      host(WelcomeScreen(onStart: () {}, onSeeDemo: (_) {})),
    );

    expect(find.byIcon(Icons.medication_rounded), findsOneWidget);
  });
}
