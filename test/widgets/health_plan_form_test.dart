import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/health_plan.dart';
import 'package:remedios_app_flutter/services/card_reader_service.dart';
import 'package:remedios_app_flutter/widgets/health_plan_form_dialog.dart';

HealthPlan? _popped;

Future<void> pumpDialog(
  WidgetTester tester, {
  HealthPlan? existing,
  CardReadResult? draft,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    final result = await showDialog<HealthPlan>(
                      context: context,
                      builder:
                          (_) => HealthPlanFormDialog(
                            healthPlan: existing,
                            draft: draft,
                          ),
                    );
                    _popped = result;
                  },
                  child: const Text('abrir'),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// V4 em passos: avança N passos (0-based; 1 = vai ao passo 2).
Future<void> goToStep(WidgetTester tester, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    _popped = null;
  });

  testWidgets('chip de operadora preenche operadora e o nome vazio', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Unimed'));
    await tester.pumpAndSettle();

    // Operadora preenchida e nome herdado (estava vazio).
    expect(find.widgetWithText(TextFormField, 'Unimed'), findsNWidgets(2));

    // Um segundo toque desmarca a operadora; o nome herado permanece.
    await tester.tap(find.widgetWithText(FilterChip, 'Unimed'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Unimed'), findsOneWidget);
  });

  testWidgets('nome é obrigatório e operadora vazia herda o nome', (
    tester,
  ) async {
    await pumpDialog(tester);

    // Sem nome, o passo 1 não avança.
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(_popped, isNull);
    expect(find.text('Informe o nome do plano'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do plano'),
      'Plano Top',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.name, 'Plano Top');
    expect(_popped!.provider, 'Plano Top');
  });

  testWidgets('rascunho da foto do cartão preenche e avisa', (tester) async {
    await pumpDialog(
      tester,
      draft: const CardReadResult(
        name: 'Unimed Nacional',
        provider: 'Unimed',
        cardNumber: '1234567890123',
        validity: '12/2029',
        coverageType: 'Ambulatorial',
        notes: 'Plano da empresa',
      ),
    );

    expect(
      find.textContaining('Preenchido pela foto do cartão'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'Unimed Nacional'),
      findsOneWidget,
    );

    // Carteirinha lida fica no passo 2.
    await goToStep(tester, 1);
    expect(find.widgetWithText(TextFormField, '1234567890123'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '12/2029'), findsOneWidget);

    // Cobertura e notas ficam no passo 3.
    await goToStep(tester, 1);
    expect(
      find.widgetWithText(TextFormField, 'Plano da empresa'),
      findsOneWidget,
    );
    // Tipo de cobertura lido cai pré-selecionado no dropdown.
    expect(find.text('Ambulatorial'), findsOneWidget);
  });

  testWidgets('edição preserva id e createdAt e preenche os campos', (
    tester,
  ) async {
    const original = HealthPlan(
      id: 'p1',
      name: 'Plano Antigo',
      provider: 'Amil',
      cardNumber: '9999',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );
    await pumpDialog(tester, existing: original);

    expect(find.text('Editar plano'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Plano Antigo'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Amil'), findsOneWidget);

    // Carteirinha no passo 2.
    await goToStep(tester, 1);
    expect(find.widgetWithText(TextFormField, '9999'), findsOneWidget);

    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do plano'),
      'Plano Renovado',
    );
    await goToStep(tester, 2);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.id, 'p1');
    expect(_popped!.name, 'Plano Renovado');
    expect(_popped!.createdAt, '2026-01-01T00:00:00.000Z');
    expect(_popped!.provider, 'Amil');
  });

  testWidgets('especialidades cobertas entram no plano salvo', (tester) async {
    // Superfície alta: o diálogo inteiro fica visível e os toques nos chips
    // não dependem de rolagem.
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do plano'),
      'Plano Completo',
    );
    // Especialidades ficam no passo 3 (cobertura).
    await goToStep(tester, 2);
    await tester.tap(find.widgetWithText(FilterChip, 'Cardiologia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Oftalmologia'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.specialties, containsAll(['Cardiologia', 'Oftalmologia']));
  });
}
