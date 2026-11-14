import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/services/ai_proxy_client.dart';
import 'package:remedios_app_flutter/services/ai_service.dart';

class FakeAiClient extends http.BaseClient {
  FakeAiClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response chat(String content) => http.Response(
      jsonEncode({
        'choices': [
          {'message': {'content': content}, 'finish_reason': 'stop'},
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

AiService serviceWith(http.BaseClient client) => AiService(
      proxyClient: AiProxyClient(client: client, isWebOverride: false),
    );

Treatment treatment(
  String id,
  String name, {
  String dosage = '50 mg',
  List<DoseTime> times = const [DoseTime(hour: 8, minute: 0)],
  DateTime? endDate,
  TreatmentFrequency frequency = TreatmentFrequency.daily,
  List<int> weekdays = const [],
}) =>
    Treatment(
      id: id,
      name: name,
      dosage: dosage,
      presentation: 'comprimido',
      instructions: '',
      startDate: DateTime(2026, 1, 1),
      endDate: endDate,
      frequency: frequency,
      doseTimes: times,
      weekdays: weekdays,
      stock: null,
      refillThreshold: null,
    );

void main() {
  group('aiExtractJson', () {
    test('lê JSON puro', () {
      expect(aiExtractJson('{"a":1}'), {'a': 1});
    });

    test('lê JSON cercado de texto e blocos de código', () {
      const content = 'Claro!\n```json\n{"a": "b"}\n```\nEspero ter ajudado.';
      expect(aiExtractJson(content), {'a': 'b'});
    });

    test('sem objeto JSON lança mensagem amigável', () {
      expect(
        () => aiExtractJson('sem json aqui'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('sanitizeInteractionReport', () {
    test('normaliza relatório completo com limites e severidade', () {
      final report = sanitizeInteractionReport({
        'summary': 'Dois pontos de atenção. ',
        'interactions': [
          {
            'severity': 'alta',
            'medications': ['varfarina', 'ibuprofeno'],
            'description': 'Risco de sangramento elevado.',
            'recommendation': 'Confirme com médico ou farmacêutico.',
          },
          {
            // Maiúsculas não são aceitas — igual ao PWA, cai em moderada.
            'severity': 'ALTA',
            'medications': ['a', 'b'],
            'description': 'Outra interação.',
            'recommendation': '',
          },
          // Sem descrição: descartado.
          {
            'severity': 'baixa',
            'medications': ['c'],
            'description': '  ',
          },
        ],
        'duplicates': [
          {
            'activeIngredient': 'Dipirona',
            'medications': ['Neosaldina', 'Novalgina'],
            'note': 'Ambos contêm dipirona.',
          },
          // Sem medicamento: descartado.
          {'activeIngredient': 'Sódio'},
        ],
        'sources': [
          {'name': 'Bulario eletrônico', 'date': '2026-01-01'},
          {'name': 'Uma empresa'},
          'entrada não objeto',
        ],
      });

      expect(report.summary, 'Dois pontos de atenção.');
      expect(report.interactions.length, 2);
      expect(
        report.interactions.first.severity,
        AiInteractionSeverity.alta,
      );
      // Severidade desconhecida cai em moderada.
      expect(
        report.interactions[1].severity,
        AiInteractionSeverity.moderada,
      );
      expect(report.duplicates.length, 1);
      expect(report.duplicates.first.activeIngredient, 'Dipirona');
      expect(report.sources, ['Bulario eletrônico (2026-01-01)', 'Uma empresa']);
    });

    test('entrada estranha vira relatório vazio sem lançar', () {
      final report = sanitizeInteractionReport('não é objeto');
      expect(report.summary, '');
      expect(report.interactions, isEmpty);
      expect(report.duplicates, isEmpty);
      expect(report.sources, isEmpty);
    });
  });

  group('consultor de horários — helpers', () {
    test('aiCleanAdvisorTime valida e padroniza', () {
      expect(aiCleanAdvisorTime('7:05'), '07:05');
      expect(aiCleanAdvisorTime('23:59'), '23:59');
      expect(aiCleanAdvisorTime('24:00'), '');
      expect(aiCleanAdvisorTime('abc'), '');
      expect(aiCleanAdvisorTime(8), '');
    });

    test('aiMinGapMinutes inclui a virada da meia-noite', () {
      // 23:00 → 07:00: gap direto 960; virada = 1440 - (1380 - 420) = 480.
      expect(aiMinGapMinutes(['23:00', '07:00']), 480);
      // 8/8h: menor gap 480.
      expect(aiMinGapMinutes(['08:00', '16:00', '00:00']), 480);
      // Um horário só: sem intervalo.
      expect(aiMinGapMinutes(['08:00']), isNull);
    });

    test('aiNormalizeMedicationName remove acentos e pontuação', () {
      expect(
        aiNormalizeMedicationName(' Losartana-Potássio 50mg '),
        'losartana potassio 50mg',
      );
    });
  });

  group('sanitizeScheduleAdvice', () {
    test('associa por id, marca mudança e monta diffs', () {
      final meds = [
        const AiScheduleMed(
          id: 'A',
          name: 'Losartana',
          dosage: '50 mg',
          instructions: '',
          times: ['08:00'],
          frequencyDays: 1,
          continuous: true,
        ),
        const AiScheduleMed(
          id: 'B',
          name: 'Metformina',
          dosage: '500 mg',
          instructions: '',
          times: ['08:00', '20:00'],
          frequencyDays: 1,
          continuous: false,
        ),
      ];

      final advice = sanitizeScheduleAdvice({
        'summary': 'Proposta de organização.',
        'suggestions': [
          {
            'medicationId': 'A',
            'medicationName': 'Nome errado não importa',
            'suggestedTimes': ['07:30'],
            'reason': 'Aproximar do café da manhã.',
            'warnings': ['confirme a receita'],
          },
          {
            'medicationId': 'B',
            'medicationName': 'Metformina',
            'suggestedTimes': ['08:00', '20:00'],
            'reason': '',
          },
          // Medicamento que não existe na lista: descartado.
          {
            'medicationId': 'Z',
            'medicationName': 'Inventado',
            'suggestedTimes': ['09:00'],
          },
        ],
      }, meds);

      expect(advice.summary, 'Proposta de organização.');
      expect(advice.suggestions.length, 2);

      final first = advice.suggestions[0];
      expect(first.medicationId, 'A');
      expect(first.medicationName, 'Losartana'); // nome real do cadastro
      expect(first.suggestedTimes, ['07:30']);
      expect(first.changed, isTrue);
      expect(first.warnings, ['confirme a receita']);

      final second = advice.suggestions[1];
      expect(second.changed, isFalse);
      expect(second.suggestedTimes, ['08:00', '20:00']);
    });

    test('associa por nome normalizado quando o id não casa', () {
      final meds = [
        const AiScheduleMed(
          id: 'A',
          name: 'Losartana Potássio',
          dosage: '',
          instructions: '',
          times: ['08:00'],
          frequencyDays: 1,
          continuous: true,
        ),
      ];
      final advice = sanitizeScheduleAdvice({
        'suggestions': [
          {
            'medicationId': 'outro-id',
            'medicationName': 'losartana potassio',
            'suggestedTimes': ['08:00'],
          },
        ],
      }, meds);
      expect(advice.suggestions.length, 1);
      expect(advice.suggestions.first.medicationId, 'A');
    });

    test('contagem divergente de doses gera warning determinístico', () {
      final meds = [
        const AiScheduleMed(
          id: 'A',
          name: 'Losartana',
          dosage: '',
          instructions: '',
          times: ['08:00', '20:00'],
          frequencyDays: 1,
          continuous: true,
        ),
      ];
      final advice = sanitizeScheduleAdvice({
        'suggestions': [
          {
            'medicationId': 'A',
            'suggestedTimes': ['08:00'], // IA devolveu 1 de 2
          },
        ],
      }, meds);

      expect(advice.suggestions.first.warnings.first, contains('1 dose'));
      expect(advice.suggestions.first.warnings.first, contains('2'));
    });

    test('intervalo abaixo de 60 minutos gera warning', () {
      final meds = [
        const AiScheduleMed(
          id: 'A',
          name: 'Losartana',
          dosage: '',
          instructions: '',
          times: ['08:00', '20:00'],
          frequencyDays: 1,
          continuous: true,
        ),
      ];
      final advice = sanitizeScheduleAdvice({
        'suggestions': [
          {
            'medicationId': 'A',
            'suggestedTimes': ['08:00', '08:30'],
          },
        ],
      }, meds);

      expect(
        advice.suggestions.first.warnings.any((w) => w.contains('0h30')),
        isTrue,
      );
    });
  });

  group('scheduleMedFromTreatment / buildScheduleDataBlock', () {
    test('frequência e duração mapeadas para o formato do PWA', () {
      final med = scheduleMedFromTreatment(
        treatment(
          't1',
          'Losartana',
          frequency: TreatmentFrequency.weekly,
          weekdays: [3, 5],
          times: const [
            DoseTime(hour: 8, minute: 0),
            DoseTime(hour: 20, minute: 30),
          ],
        ),
      );
      expect(med.frequencyDays, 7);
      expect(med.continuous, isTrue);
      expect(med.times, ['08:00', '20:30']);
      expect(med.instructions, contains('quarta'));
      expect(med.instructions, contains('sexta'));

      final med2 = scheduleMedFromTreatment(
        treatment(
          't2',
          'Antibiótico',
          frequency: TreatmentFrequency.everyOtherDay,
          endDate: DateTime(2026, 2, 1),
        ),
      );
      expect(med2.frequencyDays, 2);
      expect(med2.continuous, isFalse);
    });

    test('buildScheduleDataBlock inclui id, nome e horários', () {
      final block = buildScheduleDataBlock([
        const AiScheduleMed(
          id: 't1',
          name: 'Losartana',
          dosage: '',
          instructions: '',
          times: ['08:00'],
          frequencyDays: 1,
          continuous: true,
        ),
      ]);
      expect(block, contains('[t1]'));
      expect(block, contains('Losartana'));
      expect(block, contains('horários atuais: 08:00'));
      expect(block, contains('todos os dias'));
      expect(block, contains('uso contínuo'));
    });
  });

  group('AiService — chamadas ao proxy', () {
    test('analyzeInteractions exige pelo menos dois tratamentos', () async {
      final service = serviceWith(FakeAiClient((_) async => chat('{}')));
      await expectLater(
        service.analyzeInteractions([treatment('t1', 'Losartana')]),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('dois tratamentos'),
          ),
        ),
      );
    });

    test('analyzeInteractions sanitiza a resposta do modelo', () async {
      final service = serviceWith(
        FakeAiClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['max_tokens'], 1800);
          expect(
            (body['messages'][0]['content'] as String),
            contains('1. Losartana — 50 mg'),
          );
          return chat(
            '```json\n{"summary":"Uma atenção.",'
            '"interactions":[{"severity":"alta","medications":'
            '["losartana","ibuprofeno"],"description":"Risco de pressão '
            'descontrolada.","recommendation":"Confirme com o médico."}],'
            '"duplicates":[],"sources":[]}\n```',
          );
        }),
      );

      final report = await service.analyzeInteractions([
        treatment('t1', 'Losartana', dosage: '50 mg'),
        treatment('t2', 'Ibuprofeno', dosage: '600 mg'),
      ]);
      expect(report.summary, 'Uma atenção.');
      expect(report.interactions.length, 1);
      expect(report.interactions.first.severity, AiInteractionSeverity.alta);
    });

    test('explainMedication devolve guia sanitizado', () async {
      final service = serviceWith(
        FakeAiClient((request) async {
          final content =
              jsonDecode(request.body)['messages'][0]['content'] as String;
          expect(content, contains('Losartana'));
          expect(content, contains('dosagem: 50 mg'));
          return chat(jsonEncode({
            'whatFor': 'Controla a pressão alta.',
            'howToUse': 'Geralmente uma vez ao dia.',
            'commonSideEffects': ['Tontura'],
            'warnings': ['Evite álcool'],
            'note': 'Consulte a bula.',
          }));
        }),
      );

      final guide = await service.explainMedication(
        treatment('t1', 'Losartana', dosage: '50 mg'),
      );
      expect(guide.whatFor, 'Controla a pressão alta.');
      expect(guide.commonSideEffects, ['Tontura']);
    });

    test('suggestSchedule manda data block e sanitiza resposta', () async {
      final service = serviceWith(
        FakeAiClient((request) async {
          final content =
              jsonDecode(request.body)['messages'][0]['content'] as String;
          expect(content, contains('[t1]'));
          expect(content, contains('horários atuais: 08:00'));
          return chat(jsonEncode({
            'summary': 'Sem mudança segura.',
            'suggestions': [
              {
                'medicationId': 't1',
                'medicationName': 'Losartana',
                'suggestedTimes': ['08:00'],
                'reason': 'Mantenha.',
                'warnings': [],
              },
            ],
          }));
        }),
      );

      final advice = await service.suggestSchedule([
        treatment('t1', 'Losartana'),
      ]);
      expect(advice.suggestions.first.changed, isFalse);
    });

    test('suggestConsultationQuestions devolve perguntas', () async {
      final service = serviceWith(
        FakeAiClient((request) async {
          final content =
              jsonDecode(request.body)['messages'][0]['content'] as String;
          expect(content, contains('Adesão últimos 7 dias: 84% das doses'));
          return chat(
            '{"questions":["Levo os exames?","Preciso ajustar dose?",'
            '"Tem efeito colateral novo?"],"outro":1}',
          );
        }),
      );

      final questions = await service.suggestConsultationQuestions(
        const AiConsultationContext(
          medications: ['Losartana 50 mg — todos os dias às 08:00'],
          adherence7: '84% das doses tomadas (12 de 14)',
          adherence30: '90% das doses tomadas (54 de 60)',
        ),
      );
      expect(questions.length, 3);
      expect(questions.first, 'Levo os exames?');
    });
  });
}
