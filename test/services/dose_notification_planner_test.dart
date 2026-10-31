import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/services/dose_notification_planner.dart';

Treatment _treatment({
  String id = 't1',
  String name = 'Losartana',
  DateTime? startDate,
  DateTime? endDate,
  TreatmentFrequency frequency = TreatmentFrequency.daily,
  List<DoseTime>? doseTimes,
  bool isArchived = false,
}) {
  return Treatment(
    id: id,
    name: name,
    dosage: '50 mg',
    presentation: 'comprimido',
    instructions: 'após o café',
    startDate: startDate ?? DateTime(2026, 1, 1),
    endDate: endDate,
    frequency: frequency,
    doseTimes: doseTimes ?? const [DoseTime(hour: 8, minute: 0)],
    stock: null,
    refillThreshold: null,
    isArchived: isArchived,
  );
}

void main() {
  // Segunda-feira, 2 de novembro de 2026, 9h — data fixa para o teste ser
  // determinístico (horizonte padrão cobre 02/11 a 09/11).
  final monday9am = DateTime(2026, 11, 2, 9, 0);

  test('não agenda dose que já passou e pega a do mesmo dia ainda por vir', () {
    final planned = const DoseNotificationPlanner().plan(
      treatments: [
        _treatment(
          doseTimes: const [
            DoseTime(hour: 8, minute: 0),
            DoseTime(hour: 20, minute: 0),
          ],
        ),
      ],
      now: monday9am,
    );
    expect(planned.first.scheduledAt, DateTime(2026, 11, 2, 20, 0));
    expect(
      planned.any((dose) => dose.scheduledAt.isBefore(monday9am)),
      isFalse,
    );
  });

  test('projeta o horizonte de 7 dias em doses diárias', () {
    final planned = const DoseNotificationPlanner().plan(
      treatments: [_treatment()],
      now: monday9am,
    );
    // 08:00 do dia 02 já passou (agora é 09:00); restam 03..09/11.
    expect(planned.length, 7);
    expect(planned.first.scheduledAt, DateTime(2026, 11, 3, 8, 0));
    expect(planned.last.scheduledAt, DateTime(2026, 11, 9, 8, 0));
  });

  test('respeita dias da semana: sábado e domingo fora', () {
    final planned = const DoseNotificationPlanner().plan(
      treatments: [_treatment(frequency: TreatmentFrequency.weekdays)],
      now: monday9am,
    );
    // Horizonte: seg 02 (já passou), ter 03, qua 04, qui 05, sex 06,
    // sáb 07, dom 08, seg 09 => 5 doses.
    expect(planned.length, 5);
    final weekdays = planned.map((dose) => dose.scheduledAt.weekday).toSet();
    expect(
      weekdays.intersection({DateTime.saturday, DateTime.sunday}),
      isEmpty,
    );
  });

  test('tratamento arquivado não gera alarme', () {
    final planned = const DoseNotificationPlanner().plan(
      treatments: [_treatment(isArchived: true)],
      now: monday9am,
    );
    expect(planned, isEmpty);
  });

  test('não agenda após a data final do tratamento', () {
    final planned = const DoseNotificationPlanner().plan(
      treatments: [_treatment(endDate: DateTime(2026, 11, 4))],
      now: monday9am,
    );
    // 08:00 de 03/11 e 04/11; 05/11 em diante está fora do tratamento.
    expect(planned.map((dose) => dose.scheduledAt), [
      DateTime(2026, 11, 3, 8, 0),
      DateTime(2026, 11, 4, 8, 0),
    ]);
  });

  test('everyOtherDay segue a paridade a partir da data de início', () {
    final planned = const DoseNotificationPlanner().plan(
      treatments: [
        _treatment(
          frequency: TreatmentFrequency.everyOtherDay,
          startDate: DateTime(2026, 11, 1),
        ),
      ],
      now: monday9am,
    );
    // Início 01/11: dias com diferença par (0, 2, 4...) => 01, 03, 05, 07, 09.
    expect(planned.map((dose) => dose.scheduledAt.day), [3, 5, 7, 9]);
  });

  test('id é estável para o mesmo tratamento+horário e muda entre horários', () {
    final idA = DoseNotificationPlanner.stableId(
      't1',
      DateTime(2026, 11, 3, 8, 0),
    );
    final idB = DoseNotificationPlanner.stableId(
      't1',
      DateTime(2026, 11, 3, 8, 0),
    );
    final idC = DoseNotificationPlanner.stableId(
      't1',
      DateTime(2026, 11, 3, 20, 0),
    );
    expect(idA, idB);
    expect(idA, isNot(idC));
    expect(idA, lessThanOrEqualTo(0x7fffffff));
  });

  test('resultado vem ordenado e respeita o teto de alarmes', () {
    final minuteByMinute = List.generate(
      60,
      (minute) => DoseTime(hour: 0, minute: minute),
    );
    final planned = const DoseNotificationPlanner().plan(
      treatments: [
        _treatment(id: 'a', doseTimes: minuteByMinute),
        _treatment(id: 'b', doseTimes: minuteByMinute),
      ],
      now: monday9am,
    );
    expect(planned.length, 100);
    for (var i = 1; i < planned.length; i++) {
      expect(
        !planned[i].scheduledAt.isBefore(planned[i - 1].scheduledAt),
        isTrue,
      );
    }
  });
}
