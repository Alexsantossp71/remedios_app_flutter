import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/exam.dart';
import 'package:remedios_app_flutter/providers/exam_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SQLite é IO real: escritas dentro de testWidgets precisam de runAsync.
  // Aqui os testes são puros (sem testWidgets), então o IO direto funciona.
  setUp(() async {
    await setupTestDatabase();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Exam examOf(
    String id,
    String name,
    String status, {
    DateTime? date,
  }) {
    return Exam(
      id: id,
      name: name,
      status: status,
      date: date ?? DateTime(2026, 3, 12),
    );
  }

  test('initialize carrega exames salvos', () async {
    final provider = ExamProvider();
    await provider.saveExam(examOf('e1', 'Hemograma', ExamStatus.requested));
    await provider.saveExam(examOf('e2', 'Glicemia', ExamStatus.done));

    final reloaded = ExamProvider();
    await reloaded.initialize();

    expect(reloaded.exams.length, 2);
    expect(reloaded.isLoading, isFalse);
  });

  test('saveExam insere e atualiza pela mesma chamada', () async {
    final provider = ExamProvider();
    await provider.saveExam(examOf('e1', 'Hemograma', ExamStatus.requested));
    expect(provider.exams.single.name, 'Hemograma');

    await provider.saveExam(
      examOf('e1', 'Hemograma completo', ExamStatus.requested),
    );
    expect(provider.exams.single.name, 'Hemograma completo');
  });

  test('pendentes sobem ordenados e realizados descem do mais recente',
      () async {
    final provider = ExamProvider();
    await provider.saveExam(
      examOf('e1', 'Glicemia', ExamStatus.scheduled,
          date: DateTime(2026, 5, 1)),
    );
    await provider.saveExam(
      examOf('e2', 'Hemograma', ExamStatus.requested,
          date: DateTime(2026, 4, 1)),
    );
    await provider.saveExam(
      examOf('e3', 'ECG antigo', ExamStatus.done,
          date: DateTime(2026, 1, 1)),
    );
    await provider.saveExam(
      examOf('e4', 'ECG recente', ExamStatus.done,
          date: DateTime(2026, 2, 1)),
    );

    expect(
      provider.pendingExams.map((e) => e.name).toList(),
      ['Hemograma', 'Glicemia'],
      reason: 'pendentes em ordem crescente de data',
    );
    expect(
      provider.doneExams.map((e) => e.name).toList(),
      ['ECG recente', 'ECG antigo'],
      reason: 'realizados do mais recente para o mais antigo',
    );
    expect(provider.requestedCount, 1);
    expect(provider.scheduledCount, 1);
    expect(provider.doneCount, 2);
  });

  test('removeExam apaga do estado e do banco', () async {
    final provider = ExamProvider();
    await provider.saveExam(examOf('e1', 'Hemograma', ExamStatus.requested));
    await provider.removeExam('e1');
    expect(provider.exams, isEmpty);

    final reloaded = ExamProvider();
    await reloaded.initialize();
    expect(reloaded.exams, isEmpty);
  });

  test('round-trip preserva categoria e foto', () async {
    final provider = ExamProvider();
    await provider.saveExam(
      Exam(
        id: 'e1',
        name: 'Ultrassom',
        category: 'Imagem',
        status: ExamStatus.done,
        date: DateTime(2026, 3, 12),
        photo: 'aGVsbG8=',
        doctorName: 'Dra. Ana',
        results: 'Sem alterações',
      ),
    );

    final reloaded = ExamProvider();
    await reloaded.initialize();
    final restored = reloaded.exams.single;
    expect(restored.category, 'Imagem');
    expect(restored.photo, 'aGVsbG8=');
    expect(restored.doctorName, 'Dra. Ana');
    expect(restored.results, 'Sem alterações');
  });
}
