import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/theme/app_theme.dart';

/// Tema V3 "Clínico calmo": Nunito, azul de confiança, verde-saúde e o
/// par claro/escuro que alimenta o ThemeMode.system do MaterialApp.
void main() {
  group('AppTheme.v3 (claro)', () {
    final theme = AppTheme.light();

    test('usa Nunito e registra as cores semânticas', () {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Nunito');
      expect(theme.extension<AppSemanticColors>()!.success,
          const Color(0xFF2E9E6B));
      expect(theme.extension<AppSemanticColors>()!.danger,
          const Color(0xFFD64545));
    });

    test('primário na família do azul de confiança (canal azul dominante)', () {
      // fromSeed deriva o tom exato da paleta M3; a família é o que importa.
      final primary = theme.colorScheme.primary;
      final red = (primary.r * 255.0).round();
      final green = (primary.g * 255.0).round();
      final blue = (primary.b * 255.0).round();
      expect(blue, greaterThan(red));
      expect(blue, greaterThan(green));
    });

    test('chip selecionado fica PREENCHIDO com o azul de ação', () {
      // A seleção precisa ser impossível de não ver (queixa da v2).
      expect(theme.chipTheme.selectedColor, theme.colorScheme.primary);
      expect(theme.chipTheme.checkmarkColor, theme.colorScheme.onPrimary);
    });
  });

  group('AppTheme.dark (escuro)', () {
    final dark = AppTheme.dark();

    test('é Brightness.dark com extensão semântica clara própria', () {
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(dark.extension<AppSemanticColors>()!.success,
          const Color(0xFF63C894));
      // Fundos escuros realmente escuros (não branco de noite).
      expect(dark.scaffoldBackgroundColor, const Color(0xFF101826));
      expect(dark.cardTheme.color, const Color(0xFF17233A));
    });

    test('mantém Nunito e o mesmo idioma visual', () {
      expect(dark.textTheme.bodyMedium?.fontFamily, 'Nunito');
      expect(dark.chipTheme.selectedColor, dark.colorScheme.primary);
    });
  });

  testWidgets('AppSemanticColors.of tem fallback quando o tema não registra',
      (tester) async {
    late AppSemanticColors resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = AppSemanticColors.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // MaterialApp simples não tem a extensão: cai no padrão claro.
    expect(resolved.success, const Color(0xFF2E9E6B));
  });
}
