import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/widgets/add_health_plan_sheet.dart';

/// Pumpa um botão que abre a folha e devolve a escolha feita.
Future<void> _pumpOpener(
  WidgetTester tester,
  ValueSetter<Future<AddPlanChoice?> Function()> capture,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => capture(() => showAddHealthPlanSheet(context)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('oferece as opções imagem e manual', (tester) async {
    await _pumpOpener(tester, (open) => open());

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Enviar imagem do cartão'), findsOneWidget);
    expect(find.text('Cadastrar manualmente'), findsOneWidget);
  });

  testWidgets('retorna image ao tocar em enviar imagem', (tester) async {
    AddPlanChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                choice = await showAddHealthPlanSheet(context);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem do cartão'));
    await tester.pumpAndSettle();

    expect(choice, AddPlanChoice.image);
  });

  testWidgets('retorna manual ao tocar em cadastrar manualmente',
      (tester) async {
    AddPlanChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                choice = await showAddHealthPlanSheet(context);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar manualmente'));
    await tester.pumpAndSettle();

    expect(choice, AddPlanChoice.manual);
  });
}