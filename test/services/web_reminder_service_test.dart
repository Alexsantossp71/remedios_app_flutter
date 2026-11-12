import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/services/dose_notification_planner.dart';
import 'package:remedios_app_flutter/services/web_reminder_service.dart';

void main() {
  group('WebReminderService.dueDoses', () {
    final now = DateTime(2026, 11, 12, 14, 0);

    PlannedDose dose(String id, DateTime at) => PlannedDose(
          treatmentId: id,
          treatmentName: 'Remédio $id',
          dosage: '10mg',
          scheduledAt: at,
          notificationId: id.hashCode & 0x7fffffff,
        );

    test('dispara a dose exatamente no horário', () {
      final planned = [dose('a', now)];
      final due = WebReminderService.dueDoses(
        planned: planned,
        now: now,
        fired: {},
      );
      expect(due, hasLength(1));
      expect(due.single.treatmentId, 'a');
    });

    test('dispara dentro da janela de carência (5 min)', () {
      final planned = [dose('a', now.add(const Duration(seconds: -300)))];
      final due = WebReminderService.dueDoses(
        planned: planned,
        now: now,
        fired: {},
      );
      expect(due, hasLength(1));
    });

    test('não dispara além da janela de carência', () {
      final planned = [dose('a', now.add(const Duration(minutes: -6)))];
      final due = WebReminderService.dueDoses(
        planned: planned,
        now: now,
        fired: {},
      );
      expect(due, isEmpty);
    });

    test('não dispara dose futura', () {
      final planned = [
        dose('a', now.add(const Duration(seconds: 1))),
        dose('b', now.add(const Duration(hours: 2))),
      ];
      final due = WebReminderService.dueDoses(
        planned: planned,
        now: now,
        fired: {},
      );
      expect(due, isEmpty);
    });

    test('não dispara duas vezes a mesma dose', () {
      final planned = [dose('a', now)];
      final fired = {WebReminderService.keyOf(planned.single)};
      final due = WebReminderService.dueDoses(
        planned: planned,
        now: now,
        fired: fired,
      );
      expect(due, isEmpty);
    });

    test('ordena por horário e filtra misturando vencidas/futuras/avisadas',
        () {
      final planned = [
        dose('futuro', now.add(const Duration(minutes: 30))),
        dose('avisada', now.add(const Duration(minutes: -2))),
        dose('tardia', now.add(const Duration(minutes: -30))),
        dose('vencida-2', now.add(const Duration(minutes: -2))),
        dose('vencida-1', now.add(const Duration(minutes: -4))),
      ];
      final fired = {
        WebReminderService.keyOf(
            planned.firstWhere((d) => d.treatmentId == 'avisada')),
      };
      final due = WebReminderService.dueDoses(
        planned: planned,
        now: now,
        fired: fired,
      );
      expect(due.map((d) => d.treatmentId), ['vencida-1', 'vencida-2']);
    });

    test('keyOf é estável para o mesmo tratamento+instante', () {
      final a = dose('a', DateTime(2026, 11, 12, 8, 0));
      final b = PlannedDose(
        treatmentId: 'a',
        treatmentName: 'outro nome',
        dosage: 'outra dose',
        scheduledAt: DateTime(2026, 11, 12, 8, 0),
        notificationId: 1,
      );
      expect(WebReminderService.keyOf(a), WebReminderService.keyOf(b));
    });
  });
}
