import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/theme/app_theme.dart';
import 'package:remedios_app_flutter/widgets/empty_illustration.dart';
import 'package:remedios_app_flutter/widgets/empty_state.dart';

/// Estados vazios ilustrados: a ilustração substitui o círculo com ícone
/// quando o tema fornece uma; sem ilustração, o círculo volta.
void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      );

  testWidgets('EmptyState com ilustração desenha o CustomPaint do tema',
      (tester) async {
    await tester.pumpWidget(
      host(
        const EmptyState(
          icon: Icons.wb_sunny_outlined,
          illustration: EmptyIllustrationKind.freeDay,
          title: 'Seu dia está livre',
          description: 'Nada programado.',
        ),
      ),
    );

    expect(find.byType(EmptyIllustration), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    // O círculo de ícone é substituído pela ilustração.
    expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
    expect(find.text('Seu dia está livre'), findsOneWidget);
  });

  testWidgets('EmptyState sem ilustração mantém o círculo com ícone',
      (tester) async {
    await tester.pumpWidget(
      host(
        const EmptyState(
          icon: Icons.wb_sunny_outlined,
          title: 'Seu dia está livre',
          description: 'Nada programado.',
        ),
      ),
    );

    expect(find.byType(EmptyIllustration), findsNothing);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
  });

  testWidgets('EmptyIllustration herda o verde-saúde do tema escuro',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: EmptyIllustration(kind: EmptyIllustrationKind.pillBottle),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(EmptyIllustration),
            matching: find.byType(CustomPaint),
          ).first,
        )
        .painter! as dynamic;
    // O acento vem da extensão semântica do tema escuro.
    expect(painter.accent, const Color(0xFF63C894));
  });
}
