import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/services/dose_schedule_presets.dart';

void main() {
  group('everyIntervalHours', () {
    test('8h a partir das 08:00 gera 08:00, 16:00 e 00:00', () {
      final times = DoseSchedulePresets.everyIntervalHours(
        firstDose: const DoseTime(hour: 8, minute: 0),
        intervalHours: 8,
      );
      expect(
        times.map((time) => '${time.hour}:${time.minute.toString().padLeft(2, '0')}'),
        ['8:00', '16:00', '0:00'],
      );
    });

    test('8h a partir das 22:00 envolve a meia-noite', () {
      final times = DoseSchedulePresets.everyIntervalHours(
        firstDose: const DoseTime(hour: 22, minute: 0),
        intervalHours: 8,
      );
      expect(times.map((time) => time.hour), [22, 6, 14]);
    });

    test('24h gera um único horário', () {
      final times = DoseSchedulePresets.everyIntervalHours(
        firstDose: const DoseTime(hour: 9, minute: 30),
        intervalHours: 24,
      );
      expect(times, [const DoseTime(hour: 9, minute: 30)]);
    });

    test('intervalo inválido não quebra: devolve só a primeira dose', () {
      final times = DoseSchedulePresets.everyIntervalHours(
        firstDose: const DoseTime(hour: 9, minute: 0),
        intervalHours: 0,
      );
      expect(times, [const DoseTime(hour: 9, minute: 0)]);
    });
  });

  group('everyTimesPerDay', () {
    test('3x ao dia a partir das 07:00 gera 07:00, 15:00 e 23:00', () {
      final times = DoseSchedulePresets.everyTimesPerDay(
        firstDose: const DoseTime(hour: 7, minute: 0),
        timesPerDay: 3,
      );
      expect(
        times.map((time) => '${time.hour}:${time.minute.toString().padLeft(2, '0')}'),
        ['7:00', '15:00', '23:00'],
      );
    });

    test('2x ao dia a partir das 22:00 envolve a meia-noite', () {
      final times = DoseSchedulePresets.everyTimesPerDay(
        firstDose: const DoseTime(hour: 22, minute: 0),
        timesPerDay: 2,
      );
      expect(times.map((time) => time.hour), [10, 22]);
    });

    test('4x ao dia preserva os minutos da 1ª dose', () {
      final times = DoseSchedulePresets.everyTimesPerDay(
        firstDose: const DoseTime(hour: 6, minute: 30),
        timesPerDay: 4,
      );
      expect(
        times,
        const [
          DoseTime(hour: 0, minute: 30),
          DoseTime(hour: 6, minute: 30),
          DoseTime(hour: 12, minute: 30),
          DoseTime(hour: 18, minute: 30),
        ],
      );
    });

    test('uma toma ao dia é só a âncora e nenhuma grade repete horário', () {
      expect(
        DoseSchedulePresets.everyTimesPerDay(
          firstDose: const DoseTime(hour: 8, minute: 0),
          timesPerDay: 1,
        ),
        [const DoseTime(hour: 8, minute: 0)],
      );
      for (var count = 2; count <= 6; count++) {
        final times = DoseSchedulePresets.everyTimesPerDay(
          firstDose: const DoseTime(hour: 9, minute: 15),
          timesPerDay: count,
        );
        expect(times.toSet().length, times.length, reason: 'count=$count');
        expect(times, hasLength(count));
      }
    });
  });

  group('upcomingInstants', () {
    // Segunda-feira, 2 de novembro de 2026, 09:00 — data fixa para o teste
    // ser determinístico.
    final monday9am = DateTime(2026, 11, 2, 9, 0);

    test('ignora doses que já passaram hoje e projeta as próximas', () {
      final treatment = _treatment();
      final instants = DoseSchedulePresets.upcomingInstants(
        doseTimes: treatment.doseTimes,
        isScheduledOn: treatment.isScheduledOn,
        now: monday9am,
        count: 2,
      );
      expect(instants, [
        DateTime(2026, 11, 2, 20, 0),
        DateTime(2026, 11, 3, 8, 0),
      ]);
    });

    test('respeita a frequência de dias úteis', () {
      final treatment = _treatment(frequency: TreatmentFrequency.weekdays);
      // Quinta-feira, 5 de novembro de 2026, 09:00 — a janela de 4 doses
      // cruza o fim de semana: qui 20h, sex 8h, sex 20h e SEG 8h (sábado
      // e domingo ficam de fora).
      final thursday9am = DateTime(2026, 11, 5, 9, 0);
      final instants = DoseSchedulePresets.upcomingInstants(
        doseTimes: treatment.doseTimes,
        isScheduledOn: treatment.isScheduledOn,
        now: thursday9am,
        count: 4,
      );
      expect(instants.map((instant) => instant.weekday), [4, 5, 5, 1]);
      expect(instants.last, DateTime(2026, 11, 9, 8, 0));
    });
  });

  test('formatInstants rotula hoje, amanhã e datas futuras', () {
    final now = DateTime(2026, 11, 2, 9, 0);
    final formatted = DoseSchedulePresets.formatInstants([
      DateTime(2026, 11, 2, 20, 0),
      DateTime(2026, 11, 3, 8, 0),
      DateTime(2026, 11, 10, 8, 0),
    ], now);
    expect(formatted, 'hoje 20:00 · amanhã 08:00 · 10/11 08:00');
  });
}

Treatment _treatment({
  TreatmentFrequency frequency = TreatmentFrequency.daily,
}) {
  return Treatment(
    id: 't1',
    name: 'Losartana',
    dosage: '50 mg',
    presentation: 'comprimido',
    instructions: '',
    startDate: DateTime(2026, 1, 1),
    endDate: null,
    frequency: frequency,
    doseTimes: const [
      DoseTime(hour: 8, minute: 0),
      DoseTime(hour: 20, minute: 0),
    ],
    stock: null,
    refillThreshold: null,
  );
}
