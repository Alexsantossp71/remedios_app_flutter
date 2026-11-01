import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/models/consultation.dart';
import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/widgets/consultation_form_dialog.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

Consultation? _popped;

Future<void> pumpDialog(
  WidgetTester tester, {
  required DoctorProvider doctorProvider,
  Consultation? existing,
  String? initialDoctorId,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<DoctorProvider>.value(
      value: doctorProvider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      final result = await showDialog<Consultation>(
                        context: context,
                        builder:
                            (_) => ConsultationFormDialog(
                              initialConsultation: existing,
                              initialDoctorId: initialDoctorId,
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
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// V4 em passos: avança N passos do formulário (0-based; 1 = vai ao passo 2).
Future<void> goToStep(WidgetTester tester, int steps) async {
  for (var i = 0; i < steps; i++) {
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
  }
}

String _dateLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

void main() {
  late DoctorProvider doctorProvider;

  setUp(() async {
    _popped = null;
    await setupTestDatabase();
    doctorProvider = DoctorProvider();
    await doctorProvider.initialize();
    await doctorProvider.saveDoctor(
      const Doctor(id: 'd1', name: 'Dra. Ana', specialty: 'Cardiologia'),
    );
    await doctorProvider.saveDoctor(
      const Doctor(id: 'd2', name: 'Dr. Bruno', specialty: 'Dermatologia'),
    );
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  testWidgets('atalhos de data: chip Hoje marca a data de hoje', (
    tester,
  ) async {
    await pumpDialog(tester, doctorProvider: doctorProvider);
    await goToStep(tester, 1); // passo 2: Quando

    // Padrão do formulário novo: amanhã.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(find.textContaining(_dateLabel(tomorrow)), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Hoje'));
    await tester.pumpAndSettle();

    expect(find.textContaining(_dateLabel(DateTime.now())), findsOneWidget);
    expect(
      find
          .widgetWithText(FilterChip, 'Hoje')
          .evaluate()
          .map((e) => e.widget as FilterChip)
          .first
          .selected,
      isTrue,
    );
  });

  testWidgets('chip de motivo preenche o campo e desmarca com novo toque', (
    tester,
  ) async {
    await pumpDialog(tester, doctorProvider: doctorProvider);
    await goToStep(tester, 2); // passo 3: Motivo e retorno

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Retorno'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Retorno'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Retorno'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Retorno'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Retorno'), findsNothing);
  });

  testWidgets('agendar salva consulta com o médico e status agendada', (
    tester,
  ) async {
    await pumpDialog(tester, doctorProvider: doctorProvider);

    // Dropdown já vem no primeiro médico; motivo opcional.
    await goToStep(tester, 2);
    await tester.tap(find.text('Agendar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    // O dropdown abre no primeiro médico da lista do provider (ordenada).
    expect(_popped!.doctorId, doctorProvider.doctors.first.id);
    expect(_popped!.status, ConsultationStatus.scheduled);
    expect(_popped!.returnDate, isNull);
  });

  testWidgets('previsão de retorno aparece, pode ser trocada e é salva', (
    tester,
  ) async {
    await pumpDialog(tester, doctorProvider: doctorProvider);
    await goToStep(tester, 2); // passo 3: Motivo e retorno

    await tester.ensureVisible(find.text('Previsão de retorno'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previsão de retorno'));
    await tester.pumpAndSettle();

    // A data sugerida é 30 dias depois da consulta — muda com o toque.
    final suggestedReturn = DateTime.now().add(
      const Duration(days: 1, hours: 24 * 30),
    );
    final expectedDay = _dateLabel(suggestedReturn);
    expect(find.textContaining(expectedDay), findsOneWidget);

    await tester.tap(find.text('Agendar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.returnDate, isNotNull);
    expect(_popped!.returnDate!.isAfter(_popped!.date), isTrue);
  });

  testWidgets('edição mostra situação e preserva o id', (tester) async {
    final original = Consultation(
      id: 'c1',
      doctorId: 'd2',
      date: DateTime(2026, 3, 10, 14, 30),
      title: 'Consulta de rotina',
      status: ConsultationStatus.completed,
    );
    await pumpDialog(
      tester,
      doctorProvider: doctorProvider,
      existing: original,
    );

    expect(find.text('Editar consulta'), findsOneWidget);

    // Situação e status moram no passo 3.
    await goToStep(tester, 2);
    expect(find.text('Situação'), findsOneWidget);
    expect(find.text('Realizada'), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.id, 'c1');
    expect(_popped!.doctorId, 'd2');
    expect(_popped!.date, DateTime(2026, 3, 10, 14, 30));
  });
}
