import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/services/prescription_reader_service.dart';

void main() {
  group('PrescriptionReaderService.parseContent', () {
    test('lê medicamentos do JSON do servidor', () {
      const content = '''
{
  "medicamentos": [
    {
      "nome": "DIPIRONA",
      "dosagem": "500MG",
      "apresentacao": "comprimido",
      "intervaloHoras": 8,
      "vezesAoDia": 3,
      "horarios": ["00:00", "08:00", "16:00"],
      "duracaoDias": 5,
      "usoContinuo": false,
      "observacao": "Tomar 1 comprimido a cada 8 horas por 5 dias"
    },
    {
      "nome": "LOSARTANA",
      "dosagem": "50MG",
      "horarios": ["08:00"],
      "usoContinuo": true
    }
  ],
  "rawText": "DIPIRONA 500MG\\nTomar 1 comprimido 8/8h"
}
''';
      final result = PrescriptionReaderService.parseContent(content);

      expect(result.medicamentos, hasLength(2));
      expect(result.medicamentos[0].nome, 'DIPIRONA');
      expect(result.medicamentos[0].intervaloHoras, 8);
      expect(result.medicamentos[0].duracaoDias, 5);
      expect(result.medicamentos[1].usoContinuo, isTrue);
      expect(result.rawText, contains('DIPIRONA 500MG'));
    });

    test('tolera cerca de código e texto em volta do JSON', () {
      const content = '''
Aqui está o resultado:
```json
{"medicamentos": [{"nome": "OMEPRAZOL", "horarios": ["08:00", "20:00"]}], "rawText": "OMEPRAZOL 20MG"}
```
''';
      final result = PrescriptionReaderService.parseContent(content);
      expect(result.medicamentos.single.nome, 'OMEPRAZOL');
    });

    test('descarta entradas sem nome', () {
      const content =
          '{"medicamentos": [{"nome": "", "dosagem": "10MG"}, {"nome": "  SERTRALINA  "}], "rawText": ""}';
      final result = PrescriptionReaderService.parseContent(content);
      expect(result.medicamentos.single.nome, 'SERTRALINA');
    });

    test('horários malformados são ignorados', () {
      const content = '''
{"medicamentos": [{"nome": "X", "horarios": ["08:00", "25:00", "7h60", "abc", "8:5"]}], "rawText": ""}
''';
      final result = PrescriptionReaderService.parseContent(content);
      expect(result.medicamentos.single.horarios, ['08:00']);
    });

    test('"dia sim, dia não" do servidor vira frequência no rascunho', () {
      const content = '''
{"medicamentos": [
  {"nome": "CALCITRIOL", "horarios": ["08:00"], "diasAlternados": true},
  {"nome": "DIPIRONA", "horarios": ["08:00"]}
], "rawText": ""}
''';
      final result = PrescriptionReaderService.parseContent(content);
      final today = DateTime(2026, 11, 1);

      // Calculitriol: receita definiu a frequência; Dipirona: nada dito —
      // e ausência de informação não é inferência, o rascunho fica nulo.
      expect(
        result.medicamentos[0].toTreatmentDraft(today: today).frequency,
        TreatmentFrequency.everyOtherDay,
      );
      expect(
        result.medicamentos[1].toTreatmentDraft(today: today).frequency,
        isNull,
      );
    });

    test('sem medicamentos lança exceção com mensagem orientada', () {
      const content = '{"medicamentos": [], "rawText": "nada"}';
      expect(
        () => PrescriptionReaderService.parseContent(content),
        throwsA(
          isA<PrescriptionReaderException>().having(
            (e) => e.message,
            'message',
            contains('Não encontrei medicamentos'),
          ),
        ),
      );
    });

    test('JSON quebrado lança exceção com mensagem orientada', () {
      expect(
        () => PrescriptionReaderService.parseContent('isso não é json'),
        throwsA(isA<PrescriptionReaderException>()),
      );
    });
  });

  group('PrescriptionMedication', () {
    test('suggestedDoseTimes normaliza e ordena horários', () {
      const med = PrescriptionMedication(
        nome: 'Teste',
        horarios: ['16:00', '00:00', '08:00', '08:00', '99:99'],
      );
      expect(med.suggestedDoseTimes, [
        const DoseTime(hour: 0, minute: 0),
        const DoseTime(hour: 8, minute: 0),
        const DoseTime(hour: 16, minute: 0),
      ]);
    });

    test('toTreatmentDraft converte posologia em rascunho conferível', () {
      const med = PrescriptionMedication(
        nome: 'DIPIRONA',
        dosagem: '500MG',
        apresentacao: 'comprimido',
        horarios: ['08:00', '16:00'],
        duracaoDias: 5,
        usoContinuo: true,
        observacao: 'Tomar 1 comprimido',
      );
      final today = DateTime(2026, 10, 31);
      final draft = med.toTreatmentDraft(today: today);

      expect(draft.name, 'DIPIRONA');
      expect(draft.dosage, '500MG');
      expect(draft.presentation, 'comprimido');
      expect(draft.doseTimes, const [
        DoseTime(hour: 8, minute: 0),
        DoseTime(hour: 16, minute: 0),
      ]);
      expect(draft.endDate, DateTime(2026, 11, 5));
      expect(draft.instructions, contains('Uso contínuo'));
      expect(draft.instructions, contains('Tomar 1 comprimido'));
    });

    test('sem horários sugeridos cai no 08:00 padrão', () {
      const med = PrescriptionMedication(nome: 'X');
      final draft = med.toTreatmentDraft(today: DateTime(2026, 10, 31));
      expect(draft.doseTimes, const [DoseTime(hour: 8, minute: 0)]);
      expect(draft.endDate, isNull);
    });

    test('dias alternados construído direto carrega a frequência', () {
      const med = PrescriptionMedication(
        nome: 'PREDNISONA',
        horarios: ['08:00'],
        diasAlternados: true,
      );
      final draft = med.toTreatmentDraft(today: DateTime(2026, 10, 31));
      expect(draft.frequency, TreatmentFrequency.everyOtherDay);
    });
  });
}
