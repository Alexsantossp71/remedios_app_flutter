import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/core/lab_values.dart';

void main() {
  group('parseNumericValue', () {
    test('aceita o padrão brasileiro de decimais', () {
      expect(parseNumericValue('95'), 95);
      expect(parseNumericValue('5,4'), 5.4);
      expect(parseNumericValue('5.4'), 5.4);
      expect(
        parseNumericValue('10.200'),
        10200,
        reason: 'agrupamento de milhar',
      );
      expect(parseNumericValue('10.200,45'), 10200.45);
      expect(parseNumericValue(' 95 '), 95);
      expect(parseNumericValue('<95'.replaceAll('<', '')), 95);
    });

    test('entrada sem número vira null', () {
      expect(parseNumericValue(''), isNull);
      expect(parseNumericValue('   '), isNull);
      expect(parseNumericValue('abc'), isNull);
    });
  });

  group('parseReferenceText', () {
    test('faixa completa em variantes brasileiras', () {
      expect(parseReferenceText('70 - 99'), (low: 70.0, high: 99.0));
      expect(parseReferenceText('70 a 99'), (low: 70.0, high: 99.0));
      expect(parseReferenceText('entre 70 e 99'), (low: 70.0, high: 99.0));
      expect(parseReferenceText('0,9-1,3'), (low: 0.9, high: 1.3));
    });

    test('só limite superior', () {
      expect(parseReferenceText('até 100'), (low: null, high: 100.0));
      expect(parseReferenceText('< 100'), (low: null, high: 100.0));
      expect(parseReferenceText('≤ 100'), (low: null, high: 100.0));
    });

    test('só limite inferior', () {
      expect(parseReferenceText('≥ 4,0'), (low: 4.0, high: null));
      expect(parseReferenceText('> 4,0'), (low: 4.0, high: null));
      expect(parseReferenceText('a partir de 10'), (low: 10.0, high: null));
    });

    test('faixa ilegível vira limites nulos', () {
      expect(parseReferenceText(''), (low: null, high: null));
      expect(parseReferenceText('ver boletim'), (low: null, high: null));
    });
  });

  group('flagOf', () {
    test('classifica contra a faixa — nunca a IA', () {
      expect(flagOf(50, 70, 99), 'low');
      expect(flagOf(120, 70, 99), 'high');
      expect(flagOf(95, 70, 99), 'normal');
      expect(flagOf(95, null, null), '');
      expect(flagOf(null, 70, 99), '');
    });
  });

  group('sanitizeLabScan', () {
    test('normaliza valores, calcula flags e descarta sem nome', () {
      final scan = sanitizeLabScan({
        'labName': ' Laboratório Central ',
        'examDate': '2026-11-12',
        'resultados': [
          {
            'examName': 'Glicemia',
            'value': '115',
            'unit': 'mg/dL',
            'reference': '70 - 99',
          },
          {
            'examName': 'Hemoglobina',
            'value': '14,5',
            'unit': 'g/dL',
            'reference': '12 a 16',
          },
          {'value': 'sem nome', 'unit': ''},
        ],
      });

      expect(scan.labName, 'Laboratório Central');
      expect(scan.examDate, '2026-11-12');
      expect(scan.values.length, 2);
      expect(scan.values[0].numericValue, 115);
      expect(scan.values[0].flag, 'high');
      expect(scan.values[1].numericValue, 14.5);
      expect(scan.values[1].flag, 'normal');
    });

    test('data inválida e limite de 40 valores', () {
      final many = [
        for (var i = 0; i < 45; i++) {'examName': 'Exame $i', 'value': '$i'},
      ];
      final scan = sanitizeLabScan({
        'examDate': '12/11/2026',
        'resultados': many,
      });
      expect(scan.examDate, '');
      expect(scan.values.length, maxLabValuesPerResult);
    });

    test('entrada estranha nunca lança', () {
      final scan = sanitizeLabScan(null);
      expect(scan.labName, '');
      expect(scan.examDate, '');
      expect(scan.values, isEmpty);
    });
  });

  group('normalizeExamName', () {
    test('ignora maiúsculas e acentos', () {
      expect(
        normalizeExamName('Ácido Úrico'),
        normalizeExamName('acido urico'),
      );
      expect(normalizeExamName('Hemoglobina  Glicada'), 'hemoglobina glicada');
    });
  });

  group('computeTrends', () {
    LabValue valueOf(String name, double value, {String unit = 'mg/dL'}) {
      return LabValue(
        examName: name,
        valueText: '$value',
        numericValue: value,
        unit: unit,
        referenceLow: null,
        referenceHigh: null,
        referenceText: '',
        flag: '',
      );
    }

    test('agrupa por nome normalizado, ordena e calcula variação', () {
      final trends = computeTrends([
        LabResultLike(
          date: '2026-01-10',
          labName: 'Lab A',
          values: [valueOf('Glicemia', 95)],
        ),
        LabResultLike(
          date: '2026-03-01',
          labName: 'Lab B',
          values: [valueOf('glicemia', 110)],
        ),
        LabResultLike(
          date: '2026-02-01',
          labName: 'Lab A',
          values: [valueOf('Hemoglobina', 14)],
        ),
      ]);

      expect(trends.length, 1);
      final trend = trends.single;
      expect(trend.examName, 'Glicemia', reason: 'nome mais recente');
      expect(trend.entries.length, 2);
      expect(trend.first!.value, 95);
      expect(trend.last!.value, 110);
      expect(trend.pctChange, 16);
      expect(trend.direction, 'up');
    });

    test('variação pequena é estável e exame único não vira tendência', () {
      final trends = computeTrends([
        LabResultLike(
          date: '2026-01-10',
          values: [valueOf('TSH', 2.0, unit: 'mUI/L')],
        ),
        LabResultLike(
          date: '2026-02-10',
          values: [valueOf('TSH', 2.03, unit: 'mUI/L')],
        ),
        LabResultLike(date: '2026-03-10', values: [valueOf('Ácido Úrico', 5)]),
      ]);
      expect(trends.length, 1);
      expect(trends.single.direction, 'stable');
    });

    test('data inválida ou valor sem número não entram', () {
      final trends = computeTrends([
        LabResultLike(date: '12/03/2026', values: [valueOf('Glicemia', 95)]),
        LabResultLike(
          date: '2026-03-01',
          values: [
            LabValue(
              examName: 'Glicemia',
              valueText: 'ilegível',
              numericValue: null,
              unit: '',
              referenceLow: null,
              referenceHigh: null,
              referenceText: '',
              flag: '',
            ),
          ],
        ),
      ]);
      expect(trends, isEmpty);
    });
  });
}
