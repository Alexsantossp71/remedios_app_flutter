import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';

/// Frequência semanal ("N vezes por semana"): a regra é a lista de dias —
/// isScheduledOn é a fonte única de verdade para agenda, notificações e prévia.
void main() {
  Treatment build({
    TreatmentFrequency frequency = TreatmentFrequency.weekly,
    List<int> weekdays = const [],
  }) {
    return Treatment(
      id: 't1',
      name: 'Metotrexato',
      dosage: '15MG',
      presentation: 'comprimido',
      instructions: '',
      startDate: DateTime(2026, 10, 1), // quinta-feira
      endDate: null,
      frequency: frequency,
      doseTimes: const [DoseTime(hour: 8, minute: 0)],
      weekdays: weekdays,
      stock: null,
      refillThreshold: null,
    );
  }

  group('isScheduledOn com frequência semanal', () {
    test('só agenda nos dias escolhidos', () {
      final treatment = build(weekdays: [DateTime.saturday]);

      // Sábado, 31 de outubro de 2026.
      expect(treatment.isScheduledOn(DateTime(2026, 10, 31)), isTrue);
      // Sexta antes, domingo depois.
      expect(treatment.isScheduledOn(DateTime(2026, 10, 30)), isFalse);
      expect(treatment.isScheduledOn(DateTime(2026, 11, 1)), isFalse);
      // Sábado seguinte também tem dose.
      expect(treatment.isScheduledOn(DateTime(2026, 11, 7)), isTrue);
    });

    test('vários dias da semana ("2x por semana")', () {
      final treatment = build(weekdays: [DateTime.saturday, DateTime.sunday]);

      expect(treatment.isScheduledOn(DateTime(2026, 10, 31)), isTrue); // sáb
      expect(treatment.isScheduledOn(DateTime(2026, 11, 1)), isTrue); // dom
      expect(treatment.isScheduledOn(DateTime(2026, 11, 2)), isFalse); // seg
    });

    test('sem dia escolhido não agenda nada — a conferência decide', () {
      final treatment = build(weekdays: const []);

      expect(treatment.isScheduledOn(DateTime(2026, 10, 31)), isFalse);
      expect(treatment.isScheduledOn(DateTime(2026, 11, 7)), isFalse);
    });

    test('dia antes do início não agenda, mesmo sendo o dia certo', () {
      final treatment = build(weekdays: [DateTime.thursday]);

      // Quinta, 1º de outubro: é o dia de início, agenda.
      expect(treatment.isScheduledOn(DateTime(2026, 10, 1)), isTrue);
      // Quarta antes do início, não.
      expect(treatment.isScheduledOn(DateTime(2026, 9, 30)), isFalse);
    });
  });

  group('serialização da frequência semanal', () {
    test('toJson/fromJson preserva os dias', () {
      final treatment = build(weekdays: [DateTime.saturday, DateTime.monday]);

      final restored = Treatment.fromJson(treatment.toJson());

      expect(restored.frequency, TreatmentFrequency.weekly);
      // Ordem de inserção preservada, como doseTimes.
      expect(restored.weekdays, [6, 1]);
    });

    test('JSON antigo (sem weekdays) abre com lista vazia', () {
      final json = build().toJson()..remove('weekdays');

      final restored = Treatment.fromJson(json);

      expect(restored.frequency, TreatmentFrequency.weekly);
      expect(restored.weekdays, isEmpty);
    });

    test('copyWith troca os dias', () {
      final treatment = build(weekdays: [DateTime.saturday]);

      final updated = treatment.copyWith(weekdays: [DateTime.wednesday]);

      expect(updated.weekdays, [DateTime.wednesday]);
      expect(updated.isScheduledOn(DateTime(2026, 11, 4)), isTrue); // qua
    });
  });
}
