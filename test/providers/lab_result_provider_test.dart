import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/lab_values.dart';
import 'package:remedios_app_flutter/models/lab_result.dart';
import 'package:remedios_app_flutter/providers/lab_result_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await setupTestDatabase();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  LabValue valueOf(String name, double value, String flag) {
    return LabValue(
      examName: name,
      valueText: '$value',
      numericValue: value,
      unit: 'mg/dL',
      referenceLow: flag == 'high' ? 70 : (flag == 'low' ? null : 70),
      referenceHigh: flag == 'low' ? 60 : (flag == 'high' ? 99 : 99),
      referenceText: '70 - 99',
      flag: flag,
    );
  }

  test('initialize carrega laudos e recalcula flags do JSON', () async {
    final provider = LabResultProvider();
    await provider.saveResult(
      LabResult(
        id: 'l1',
        date: DateTime(2026, 3, 12),
        labName: 'Lab Central',
        values: [valueOf('Glicemia', 115, 'high')],
        notes: 'Em jejum',
      ),
    );

    final reloaded = LabResultProvider();
    await reloaded.initialize();

    expect(reloaded.results.length, 1);
    final value = reloaded.results.single.values.single;
    expect(value.examName, 'Glicemia');
    expect(value.numericValue, 115);
    expect(value.flag, 'high');
    expect(reloaded.isLoading, isFalse);
  });

  test('resultsByDate ordena do mais recente para o mais antigo', () async {
    final provider = LabResultProvider();
    await provider.saveResult(
      LabResult(
        id: 'l1',
        date: DateTime(2026, 1, 10),
        values: [valueOf('Glicemia', 95, 'normal')],
      ),
    );
    await provider.saveResult(
      LabResult(
        id: 'l2',
        date: DateTime(2026, 3, 1),
        values: [valueOf('Glicemia', 110, 'high')],
      ),
    );

    expect(provider.resultsByDate.map((r) => r.id).toList(), ['l2', 'l1']);
    expect(
      provider.alteredCount,
      1,
      reason: '95 na faixa não conta; 110 acima conta',
    );
  });

  test('trends deriva evolução dos marcadores repetidos', () async {
    final provider = LabResultProvider();
    await provider.saveResult(
      LabResult(
        id: 'l1',
        date: DateTime(2026, 1, 10),
        values: [valueOf('Glicemia', 95, 'normal')],
      ),
    );
    await provider.saveResult(
      LabResult(
        id: 'l2',
        date: DateTime(2026, 3, 1),
        values: [valueOf('glicemia', 110, 'high')],
      ),
    );

    final trends = provider.trends;
    expect(trends.length, 1);
    expect(trends.single.examName, 'Glicemia');
    expect(trends.single.direction, 'up');
    expect(trends.single.pctChange, 16);
  });

  test('saveResult atualiza pelo id e removeResult apaga', () async {
    final provider = LabResultProvider();
    await provider.saveResult(
      LabResult(
        id: 'l1',
        date: DateTime(2026, 3, 12),
        values: [valueOf('Glicemia', 115, 'high')],
      ),
    );
    await provider.saveResult(
      LabResult(
        id: 'l1',
        date: DateTime(2026, 3, 12),
        labName: 'Lab B',
        values: [valueOf('Glicemia', 90, 'normal')],
      ),
    );
    expect(provider.results.single.labName, 'Lab B');
    expect(provider.results.single.values.single.flag, 'normal');

    await provider.removeResult('l1');
    expect(provider.results, isEmpty);

    final reloaded = LabResultProvider();
    await reloaded.initialize();
    expect(reloaded.results, isEmpty);
  });

  test('valuesJson round-trip preserva os valores', () {
    final result = LabResult(
      id: 'l1',
      date: DateTime(2026, 3, 12),
      values: [
        valueOf('Glicemia', 115, 'high'),
        valueOf('Hemoglobina', 14.5, 'normal'),
      ],
    );
    final restored = LabResult.valuesFromJsonText(result.valuesJson);
    expect(restored.length, 2);
    expect(restored[0].examName, 'Glicemia');
    expect(restored[0].numericValue, 115);
    expect(restored[0].flag, 'high');
    expect(restored[1].numericValue, 14.5);
    expect(LabResult.valuesFromJsonText(null), isEmpty);
    expect(LabResult.valuesFromJsonText('não é json'), isEmpty);
  });
}
