import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/design/brand_colors.dart';
import 'package:remedios_app_flutter/core/theme/app_theme.dart';

/// Tema V5 "Identidade do PWA": Inter, paleta teal do app irmão
/// "Remédios na Hora" e o par claro/escuro que alimenta o
/// ThemeMode.system do MaterialApp. O V3 segue como legado compilável.
void main() {
  group('AppTheme.v5 (claro)', () {
    final theme = AppTheme.light();

    test('usa Inter e registra as cores semânticas', () {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.extension<AppSemanticColors>()!.success,
          const Color(0xFF2E9E6B));
      expect(
        theme.extension<AppSemanticColors>()!.danger,
        BrandColors.red,
      );
      expect(
        theme.extension<AppSemanticColors>()!.warning,
        BrandColors.yellow,
      );
    });

    test('primário na família do teal de ação (canal verde-azulado)', () {
      // fromSeed deriva o tom exato da paleta M3; a família é o que importa.
      final primary = theme.colorScheme.primary;
      final red = (primary.r * 255.0).round();
      final green = (primary.g * 255.0).round();
      final blue = (primary.b * 255.0).round();
      expect(green, greaterThan(red));
      expect(blue, greaterThan(red));
    });

    test('chip selecionado fica PREENCHIDO com o teal de ação', () {
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
      expect(dark.scaffoldBackgroundColor, BrandColors.darkCanvas);
      expect(dark.cardTheme.color, BrandColors.darkSurface);
    });

    test('mantém Inter e o mesmo idioma visual', () {
      expect(dark.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(dark.chipTheme.selectedColor, dark.colorScheme.primary);
    });
  });

  group('AppTheme.v3 legado', () {
    test('continua compilando com a identidade original intacta', () {
      final v3 = AppTheme.v3();
      expect(v3.textTheme.bodyMedium?.fontFamily, 'Nunito');
      expect(
        v3.extension<AppSemanticColors>()!.danger,
        const Color(0xFFD64545),
      );
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
