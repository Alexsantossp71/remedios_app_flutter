import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/models/exam.dart';
import 'package:remedios_app_flutter/providers/exam_provider.dart';
import 'package:remedios_app_flutter/screens/exams_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExamProvider exams;

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    exams = ExamProvider();
    await exams.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Widget host() {
    return ChangeNotifierProvider.value(
      value: exams,
      child: const MaterialApp(home: ExamsScreen()),
    );
  }

  testWidgets('estado vazio mostra a chamada para registrar', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum exame registrado'), findsOneWidget);
    expect(find.text('Registrar exame'), findsOneWidget);
  });

  testWidgets('lista pendentes e realizados com chips de status e stats', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await exams.saveExam(
        Exam(
          id: 'e1',
          name: 'Hemograma completo',
          category: 'Laboratório',
          status: ExamStatus.requested,
          date: DateTime(2026, 3, 12),
        ),
      );
      await exams.saveExam(
        Exam(
          id: 'e2',
          name: 'ECG',
          status: ExamStatus.done,
          date: DateTime(2026, 2, 1),
          results: 'Traço normal',
        ),
      );
      await exams.initialize();
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Hemograma completo'), findsOneWidget);
    expect(find.text('ECG'), findsOneWidget);
    expect(find.text('Solicitado'), findsOneWidget);
    expect(find.text('Realizado'), findsOneWidget);
    expect(find.text('Laboratório'), findsOneWidget);
    expect(find.text('Pendentes'), findsOneWidget);
    expect(find.text('Realizados'), findsNWidgets(2));
    expect(find.text('Pedido em 12/03/2026'), findsOneWidget);
    expect(find.text('Realizado em 01/02/2026'), findsOneWidget);
    expect(find.text('Traço normal'), findsOneWidget);
  });

  testWidgets('exame agendado exibe horário e prefixo de agendamento', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await exams.saveExam(
        Exam(
          id: 'e1',
          name: 'Ressonância',
          status: ExamStatus.scheduled,
          date: DateTime(2026, 4, 20),
          time: '14:30',
          place: 'Clínica Imagem',
        ),
      );
      await exams.initialize();
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Agendado'), findsWidgets);
    expect(find.text('Agendado para 20/04/2026 às 14:30'), findsOneWidget);
    expect(find.text('Clínica Imagem'), findsOneWidget);
  });
}
