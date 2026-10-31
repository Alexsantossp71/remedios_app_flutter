import '../models/treatment.dart';

/// Presets que tornam o cadastro de horários um trabalho de um toque.
///
/// Puro e sem Flutter de propósito: as regras de geração são a parte que
/// gera dúvida real no usuário ("de 8 em 8 horas começa quando?") e pedem
/// teste unitário direto. A frequência (dias úteis, dia sim dia não) não é
/// duplicada aqui: [upcomingInstants] recebe a regra como callback, e o
/// formulário passa `Treatment.isScheduledOn` — fonte única de verdade.
class DoseSchedulePresets {
  DoseSchedulePresets._();

  /// Gera os horários de um dia para doses em intervalo fixo de
  /// [intervalHours], ancoradas no horário da primeira dose. A convenção
  /// médica de "de 8 em 8 horas" é a partir da 1ª toma, não do relógio:
  /// 1ª dose às 22:00 gera 22:00, 06:00 e 14:00 — e 08:00 gera 08:00,
  /// 16:00 e 00:00. O ciclo fecha em 24h: um intervalo de 8h significa
  /// 3 tomas por dia, inclusive a que cruza a meia-noite.
  static List<DoseTime> everyIntervalHours({
    required DoseTime firstDose,
    required int intervalHours,
  }) {
    if (intervalHours <= 0 || intervalHours >= 24 * 60) return [firstDose];
    final step = intervalHours * 60;
    final dayMinutes = 24 * 60;
    final dosesPerDay = (dayMinutes / step).round();
    return [
      for (var i = 0; i < dosesPerDay; i++)
        _fromMinutes((firstDose.minutesSinceMidnight + i * step) % dayMinutes),
    ];
  }

  static DoseTime _fromMinutes(int minutes) =>
      DoseTime(hour: minutes ~/ 60, minute: minutes % 60);

  /// Chips de rotina: um toque marca, outro desmarca.
  static const List<({String label, DoseTime time})> routinePresets = [
    (label: 'Café 08:00', time: DoseTime(hour: 8, minute: 0)),
    (label: 'Almoço 12:00', time: DoseTime(hour: 12, minute: 0)),
    (label: 'Janta 19:00', time: DoseTime(hour: 19, minute: 0)),
    (label: 'Dormir 22:00', time: DoseTime(hour: 22, minute: 0)),
  ];

  /// Próximos [count] momentos de dose a partir de [now], seguindo a mesma
  /// regra de agendamento que gera os DoseEvent.
  static List<DateTime> upcomingInstants({
    required List<DoseTime> doseTimes,
    required bool Function(DateTime day) isScheduledOn,
    required DateTime now,
    int count = 3,
  }) {
    final instants = <DateTime>[];
    var day = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 60 && instants.length < count; i++) {
      if (isScheduledOn(day)) {
        for (final time in doseTimes) {
          final instant = DateTime(
            day.year,
            day.month,
            day.day,
            time.hour,
            time.minute,
          );
          if (!instant.isAfter(now)) continue;
          instants.add(instant);
          if (instants.length == count) break;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return instants;
  }

  /// "hoje 20:00 · amanhã 08:00 · 10/11 08:00"
  static String formatInstants(List<DateTime> instants, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return instants.map((instant) {
      final time =
          '${instant.hour.toString().padLeft(2, '0')}:${instant.minute.toString().padLeft(2, '0')}';
      final day = DateTime(instant.year, instant.month, instant.day);
      final difference = day.difference(today).inDays;
      if (difference == 0) return 'hoje $time';
      if (difference == 1) return 'amanhã $time';
      return '${instant.day.toString().padLeft(2, '0')}/${instant.month.toString().padLeft(2, '0')} $time';
    }).join(' · ');
  }
}
