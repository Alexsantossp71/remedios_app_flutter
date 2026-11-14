import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/design/app_shell.dart';
import 'package:remedios_app_flutter/core/design/brand_colors.dart';
import 'package:remedios_app_flutter/core/design/brand_mark.dart';
import 'package:remedios_app_flutter/core/design/dashboard_hero.dart';
import 'package:remedios_app_flutter/core/design/quick_action.dart';
import 'package:remedios_app_flutter/core/design/record_card.dart';
import 'package:remedios_app_flutter/core/design/stat_card.dart';
import 'package:remedios_app_flutter/core/theme/app_theme.dart';

/// Design system V5 — os componentes de assinatura replicados do PWA
/// "Remédios na Hora" e os temas claro/escuro que usam a paleta teal.
void main() {
  group('Tema V5 (claro)', () {
    final theme = AppTheme.light();

    test('usa Inter e os hexes da paleta do PWA', () {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.scaffoldBackgroundColor, BrandColors.canvas);
      // fromSeed deriva o tom exato da paleta M3; a família teal é o que
      // importa (verde-azulado dominante sobre o vermelho).
      final primary = theme.colorScheme.primary;
      final red = (primary.r * 255.0).round();
      final green = (primary.g * 255.0).round();
      final blue = (primary.b * 255.0).round();
      expect(green, greaterThan(red));
      expect(blue, greaterThan(red));
    });

    test('semânticas de perigo/alerta vêm do PWA', () {
      final semantic = theme.extension<AppSemanticColors>()!;
      expect(semantic.success, const Color(0xFF2E9E6B));
      expect(semantic.danger, BrandColors.red);
      expect(semantic.warning, BrandColors.yellow);
    });

    test('chip selecionado fica PREENCHIDO com o teal de ação', () {
      expect(theme.chipTheme.selectedColor, theme.colorScheme.primary);
      expect(theme.chipTheme.checkmarkColor, theme.colorScheme.onPrimary);
    });
  });

  group('Tema V5 (escuro)', () {
    final dark = AppTheme.dark();

    test('superfícies slate do PWA', () {
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, BrandColors.darkCanvas);
      expect(dark.cardTheme.color, BrandColors.darkSurface);
      expect(dark.textTheme.bodyMedium?.fontFamily, 'Inter');
    });
  });

  group('Tema V3 legado segue compilando com a identidade original', () {
    test('Nunito e azul de confiança intactos', () {
      final v3 = AppTheme.v3();
      expect(v3.textTheme.bodyMedium?.fontFamily, 'Nunito');
      expect(
        v3.extension<AppSemanticColors>()!.danger,
        const Color(0xFFD64545),
      );
    });
  });

  testWidgets('AppShell pinta o palco e repassa o filho',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AppShell(child: Text('palco'))),
      ),
    );
    expect(find.text('palco'), findsOneWidget);
  });

  testWidgets('DashboardHero renderiza o conteúdo sobre o gradiente',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: DashboardHero(child: Text('herói')),
          ),
        ),
      ),
    );
    expect(find.text('herói'), findsOneWidget);
  });

  testWidgets('StatCard mostra valor e rótulo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: StatCard(
            icon: Icons.medication_rounded,
            value: '3/4',
            label: 'doses de hoje',
          ),
        ),
      ),
    );
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('doses de hoje'), findsOneWidget);
  });

  testWidgets('QuickAction dispara onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: QuickAction(
            icon: Icons.add,
            label: 'Novo lembrete',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Novo lembrete'));
    expect(taps, 1);
  });

  testWidgets('RecordCard renderiza conteúdo e dispara onTap',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RecordCard(
            onTap: () => taps++,
            child: const Text('registro'),
          ),
        ),
      ),
    );
    expect(find.text('registro'), findsOneWidget);
    await tester.tap(find.text('registro'));
    expect(taps, 1);
  });

  testWidgets('BrandMark desenha o glifo branco no gradiente',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: BrandMark(size: 48)),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, Colors.white);
    expect(icon.size, closeTo(48 * .52, .01));
  });

  testWidgets('tema escuro mantém os componentes de assinatura legíveis',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Column(
            children: [
              StatCard(
                icon: Icons.event_available_rounded,
                value: '2',
                label: 'consultas no dia',
              ),
              QuickAction(icon: Icons.add, label: 'Ação rápida'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Ação rápida'), findsOneWidget);
  });
}
