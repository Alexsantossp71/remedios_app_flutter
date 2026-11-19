import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/exam.dart';

void main() {
  group('ExamStatus', () {
    test('rótulos em português do fluxo pedido → agendado → realizado', () {
      expect(ExamStatus.label(ExamStatus.requested), 'Solicitado');
      expect(ExamStatus.label(ExamStatus.scheduled), 'Agendado');
      expect(ExamStatus.label(ExamStatus.done), 'Realizado');
      expect(ExamStatus.label('desconhecido'), 'desconhecido');
    });
  });

  group('Exam', () {
    test('create gera id e createdAt em UTC', () {
      final exam = Exam.create(
        name: 'Hemograma completo',
        date: DateTime(2026, 3, 12),
      );
      expect(exam.id, isNotEmpty);
      expect(exam.createdAt, isNotNull);
      expect(exam.createdAt!.isUtc, isTrue);
      expect(exam.status, ExamStatus.requested);
    });

    test('datePrefix muda conforme o status', () {
      final exam = Exam(id: 'e1', name: 'Glicemia', date: DateTime(2026));
      expect(exam.datePrefix, 'Pedido em');
      expect(
        exam.copyWith(status: ExamStatus.scheduled).datePrefix,
        'Agendado para',
      );
      expect(exam.copyWith(status: ExamStatus.done).datePrefix, 'Realizado em');
    });

    test('fromJson descarta categoria e status desconhecidos', () {
      final exam = Exam.fromJson({
        'id': 'e1',
        'name': 'Ultrassom',
        'category': 'Category inventada',
        'status': 'status inventado',
        'date': DateTime(2026, 3, 12).toIso8601String(),
      });
      expect(exam.category, '');
      expect(exam.status, ExamStatus.requested);
    });

    test('round-trip toJson → fromJson preserva todos os campos', () {
      final exam = Exam(
        id: 'e1',
        name: 'Hemograma completo, Glicemia',
        category: 'Laboratório',
        status: ExamStatus.scheduled,
        date: DateTime(2026, 3, 12, 9, 30),
        time: '09:30',
        photo: 'aGVsbG8=',
        doctorId: 'd1',
        doctorName: 'Dra. Ana',
        place: 'Laboratório Central',
        results: 'Sem alterações',
        createdAt: DateTime.utc(2026, 3, 1),
      );

      final restored = Exam.fromJson(exam.toJson());
      expect(restored.id, exam.id);
      expect(restored.name, exam.name);
      expect(restored.category, exam.category);
      expect(restored.status, exam.status);
      expect(restored.date, exam.date);
      expect(restored.time, exam.time);
      expect(restored.photo, exam.photo);
      expect(restored.doctorId, exam.doctorId);
      expect(restored.doctorName, exam.doctorName);
      expect(restored.place, exam.place);
      expect(restored.results, exam.results);
    });

    test('copyWith limpa time e photo com flags explícitas', () {
      final exam = Exam(
        id: 'e1',
        name: 'Glicemia',
        date: DateTime(2026),
        time: '09:30',
        photo: 'aGVsbG8=',
      );
      expect(exam.copyWith().time, '09:30');
      expect(exam.copyWith().photo, 'aGVsbG8=');
      expect(exam.copyWith(clearTime: true).time, isNull);
      expect(exam.copyWith(clearPhoto: true).photo, isNull);
      expect(exam.copyWith(time: '10:00').time, '10:00');
    });
  });
}
