import 'dart:convert';

import '../models/treatment.dart';
import 'ai_proxy_client.dart';

/// Ferramentas de IA do PWA "Remédio na Hora" portadas para o Flutter via
/// mesmo proxy (Cloudflare Worker). As funções são informativas: nenhum
/// resultado altera dados do app por conta própria — a decisão é sempre do
/// usuário, e os avisos reforçam a confirmação com médico/farmacêutico.
///
/// As respostas do modelo são sempre sanitizadas antes de chegar à
/// interface: texto cortado em limites definidos, listas filtradas e,
/// no consultor de horários, checagens determinísticas (contagem de doses
/// e intervalo mínimo) que não dependem da honestidade do modelo.
class AiService {
  AiService({AiProxyClient? proxyClient})
      : _proxy = proxyClient ?? AiProxyClient();

  final AiProxyClient _proxy;

  // ===== Interações e duplicidades =====

  /// Analisa duplicidades de princípio ativo e interações entre os
  /// tratamentos ativos. Exige pelo menos dois tratamentos com nome.
  Future<AiInteractionReport> analyzeInteractions(
    List<Treatment> treatments,
  ) async {
    final list = treatments
        .map(
          (item) => (
            name: item.name.trim(),
            dosage: item.dosage.trim(),
          ),
        )
        .where((item) => item.name.isNotEmpty)
        .toList();
    if (list.length < 2) {
      throw AiException(
        'Cadastre pelo menos dois tratamentos para a análise de interações.',
      );
    }

    final medicationLines = <String>[];
    for (var index = 0; index < list.length; index++) {
      final dosage = list[index].dosage.isEmpty ? '' : ' — ${list[index].dosage}';
      medicationLines.add('${index + 1}. ${list[index].name}$dosage');
    }

    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content':
              '$interactionsPrompt\n\nMedicamentos em uso:\n${medicationLines.join('\n')}',
        },
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 1800,
      temperature: 0.1,
    );

    return sanitizeInteractionReport(aiExtractJson(content));
  }

  // ===== Bula simplificada =====

  /// Explica um medicamento em linguagem leiga, considerando a dosagem e
  /// as instruções cadastradas no tratamento.
  Future<AiMedicationGuide> explainMedication(Treatment treatment) async {
    final name = treatment.name.trim();
    if (name.isEmpty) {
      throw AiException('Informe o nome do medicamento.');
    }
    final context = [
      name,
      treatment.dosage.trim().isNotEmpty
          ? 'dosagem: ${treatment.dosage.trim()}'
          : '',
      treatment.instructions.trim().isNotEmpty
          ? 'instruções: ${treatment.instructions.trim()}'
          : '',
    ].where((part) => part.isNotEmpty).join(' | ');

    final content = await _proxy.chatCompletion(
      messages: [
        {'role': 'user', 'content': '$guidePrompt\n\nMedicamento: $context'},
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 1200,
      temperature: 0.3,
    );

    return sanitizeMedicationGuide(aiExtractJson(content));
  }

  // ===== Consultor de horários =====

  /// Sugere redistribuição de horários entre as doses do dia, sem alterar
  /// dose, frequência ou duração. Cada sugestão referencia o id do
  /// tratamento; sugestões para ids desconhecidos são descartadas.
  Future<AiScheduleAdvice> suggestSchedule(List<Treatment> treatments) async {
    final meds = treatments.map(scheduleMedFromTreatment).toList();
    if (meds.isEmpty) {
      throw AiException(
        'Cadastre tratamentos com horários para a IA sugerir melhorias.',
      );
    }

    // Tarefa de JSON curto: prioriza um modelo Flash rápido (igual ao PWA).
    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content':
              '$schedulePrompt\n\n${buildScheduleDataBlock(meds)}',
        },
      ],
      model: 'z-ai/glm-5.3-flash',
      maxTokens: 1100,
      temperature: 0.2,
      requestTimeout: const Duration(seconds: 9),
      maxModels: 2,
    );

    return sanitizeScheduleAdvice(aiExtractJson(content), meds);
  }

  // ===== Perguntas para a consulta =====

  /// Sugere de 3 a 5 perguntas personalizadas para levar à consulta,
  /// combinando tratamentos, adesão e dificuldades recentes.
  Future<List<String>> suggestConsultationQuestions(
    AiConsultationContext context,
  ) async {
    final payload = [
      context.medications.isNotEmpty
          ? 'Medicamentos em uso:\n${context.medications.map((m) => '- $m').join('\n')}'
          : 'Medicamentos: nenhum cadastrado.',
      'Adesão últimos 7 dias: ${context.adherence7}',
      'Adesão últimos 30 dias: ${context.adherence30}',
      context.difficulties.isNotEmpty
          ? 'Doses com mais perda:\n${context.difficulties.map((d) => '- $d').join('\n')}'
          : 'Doses com mais perda: nenhuma.',
      context.pendingExams.isNotEmpty
          ? 'Exames pendentes:\n${context.pendingExams.map((e) => '- $e').join('\n')}'
          : 'Exames pendentes: nenhum.',
    ].join('\n\n');

    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content': '$questionsPrompt\n\nDados do paciente:\n$payload',
        },
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 700,
      temperature: 0.4,
    );

    return sanitizeConsultationQuestions(aiExtractJson(content));
  }
}

// ===== Contexto de consulta (montado pela tela a partir dos providers) =====

/// Dados agregados enviados ao modelo para sugerir perguntas da consulta.
/// Tudo é texto curto já formatado — nada de ids internos.
class AiConsultationContext {
  const AiConsultationContext({
    required this.medications,
    required this.adherence7,
    required this.adherence30,
    this.difficulties = const [],
    this.pendingExams = const [],
  });

  /// Ex.: "Losartana 50mg — todos os dias às 08:00".
  final List<String> medications;
  final String adherence7;
  final String adherence30;

  /// Ex.: "Noite (18h–23h): 4 doses não tomadas de 20".
  final List<String> difficulties;
  final List<String> pendingExams;
}

// ===== Modelos de resultado (espelhos dos tipos do PWA) =====

class AiInteractionAlert {
  const AiInteractionAlert({
    required this.severity,
    required this.medications,
    required this.description,
    required this.recommendation,
  });

  final AiInteractionSeverity severity;
  final List<String> medications;
  final String description;
  final String recommendation;
}

class AiDuplicateGroup {
  const AiDuplicateGroup({
    required this.activeIngredient,
    required this.medications,
    required this.note,
  });

  final String activeIngredient;
  final List<String> medications;
  final String note;
}

class AiInteractionReport {
  const AiInteractionReport({
    required this.summary,
    required this.duplicates,
    required this.interactions,
    required this.sources,
  });

  final String summary;
  final List<AiDuplicateGroup> duplicates;
  final List<AiInteractionAlert> interactions;
  final List<String> sources;

  bool get isEmpty =>
      summary.isEmpty && duplicates.isEmpty && interactions.isEmpty;
}

enum AiInteractionSeverity { alta, moderada, baixa }

class AiMedicationGuide {
  const AiMedicationGuide({
    required this.whatFor,
    required this.howToUse,
    required this.commonSideEffects,
    required this.warnings,
    required this.note,
  });

  final String whatFor;
  final String howToUse;
  final List<String> commonSideEffects;
  final List<String> warnings;
  final String note;
}

/// Medicamento no formato do consultor de horários (id estável: a resposta
/// do modelo referencia o id, não o nome).
class AiScheduleMed {
  const AiScheduleMed({
    required this.id,
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
    required this.frequencyDays,
    required this.continuous,
  });

  final String id;
  final String name;
  final String dosage;
  final String instructions;

  /// Horários 'HH:MM'.
  final List<String> times;

  /// 1 = todos os dias; N = a cada N dias.
  final int frequencyDays;
  final bool continuous;
}

class AiScheduleSuggestion {
  const AiScheduleSuggestion({
    required this.medicationId,
    required this.medicationName,
    required this.suggestedTimes,
    required this.reason,
    required this.warnings,
    required this.changed,
    required this.minGapMinutes,
  });

  final String medicationId;
  final String medicationName;

  /// Horários sugeridos 'HH:MM', validados, sem repetição e ordenados.
  final List<String> suggestedTimes;
  final String reason;
  final List<String> warnings;
  final bool changed;
  final int? minGapMinutes;
}

class AiScheduleAdvice {
  const AiScheduleAdvice({
    required this.summary,
    required this.suggestions,
  });

  final String summary;
  final List<AiScheduleSuggestion> suggestions;
}

// ===== Conversão Treatment → AiScheduleMed =====

/// Mapeia o tratamento cadastrado para o formato do consultor. A frequência
/// semanal/útil do Flutter não existe no modelo do PWA: entra como
/// `frequencyDays` equivalente e a restrição de dias vira instrução de
/// texto, para o modelo não sugerir horários em dias que não existem.
AiScheduleMed scheduleMedFromTreatment(Treatment treatment) {
  var instructions = treatment.instructions.trim();
  switch (treatment.frequency) {
    case TreatmentFrequency.weekdays:
      instructions = [
        if (instructions.isNotEmpty) instructions,
        'apenas de segunda a sexta',
      ].join(' — ');
    case TreatmentFrequency.weekly:
      const labels = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
      final days = treatment.weekdays.map((day) => labels[day - 1]).join(', ');
      instructions = [
        if (instructions.isNotEmpty) instructions,
        if (days.isNotEmpty) 'apenas em: $days',
      ].join(' — ');
    case TreatmentFrequency.daily:
    case TreatmentFrequency.everyOtherDay:
      break;
  }
  final frequencyDays = switch (treatment.frequency) {
    TreatmentFrequency.daily || TreatmentFrequency.weekdays => 1,
    TreatmentFrequency.everyOtherDay => 2,
    TreatmentFrequency.weekly => 7,
  };
  return AiScheduleMed(
    id: treatment.id,
    name: treatment.name.trim(),
    dosage: treatment.dosage.trim(),
    instructions: instructions,
    times: treatment.doseTimes
        .map((time) =>
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
        .toList(),
    frequencyDays: frequencyDays,
    continuous: treatment.endDate == null,
  );
}

/// Bloco de dados enviado ao modelo — mesma linha por medicamento do PWA
/// (`[id] | nome | dosagem | instruções | frequência | duração | horários`).
String buildScheduleDataBlock(List<AiScheduleMed> medications) {
  final lines = medications.map((med) {
    final frequency = med.frequencyDays > 1
        ? 'a cada ${med.frequencyDays} dias'
        : 'todos os dias';
    final duration = med.continuous ? 'uso contínuo' : 'por prazo determinado';
    final dosage = med.dosage.isEmpty ? 'dosagem não informada' : med.dosage;
    final instructions =
        med.instructions.isEmpty ? 'nenhuma' : med.instructions;
    final times =
        med.times.isNotEmpty ? med.times.join(', ') : 'nenhum';
    final parts = [
      '[${med.id}]',
      med.name,
      dosage,
      'instruções: $instructions',
      frequency,
      duration,
      'horários atuais: $times',
    ];
    return '- ${parts.join(' | ')}';
  });
  return 'Medicamentos do paciente (id | nome | dosagem | instruções | '
      'frequência | duração | horários atuais):\n${lines.join('\n')}';
}

// ===== Prompts (portados verbatim do nvidiaService.ts do PWA) =====

const String interactionsPrompt =
    'Analise a lista de medicamentos de um paciente para apontar possíveis '
    'duplicidades de princípio ativo e interações medicamentosas relevantes. '
    'Você é um assistente informativo, não um farmacêutico responsável pelo '
    'paciente.\n\n'
    'Responda APENAS com um JSON válido, sem nenhum texto antes ou depois, '
    'neste formato:\n'
    '{"summary":"...","duplicates":[{"activeIngredient":"...","medications":'
    '["..."],"note":"..."}],"interactions":[{"severity":"alta",'
    '"medications":["..."],"description":"...","recommendation":"..."}],'
    '"sources":[{"name":"fonte identificável consultada","date":"data da '
    'edição ou AAAA-MM-DD"}]}\n\n'
    'Regras:\n'
    '- Considere nomes comerciais e genéricos, mas sinalize incerteza quando '
    'nomes semelhantes puderem ser confundidos.\n'
    '- duplicates: grupos da lista que compartilham princípio ativo com risco '
    'de duplicidade; não afirme equivalência sem segurança.\n'
    '- interactions: somente combinações clinicamente reconhecidas; severity '
    'exatamente "alta", "moderada" ou "baixa".\n'
    '- description: possível consequência em linguagem simples. '
    'recommendation: orientar a confirmar com médico ou farmacêutico.\n'
    '- Nunca recomende iniciar, suspender, substituir, aumentar ou reduzir '
    'medicamento, dose ou frequência.\n'
    '- Nunca declare que uma combinação é "segura" nem que "não há risco". '
    'Ausência de alertas não exclui interações.\n'
    '- sources: inclua apenas fontes clínicas realmente consultadas e '
    'identificáveis. Informe data/edição apenas se conhecida. Nunca invente '
    'fonte ou data; se não houver, devolva [].\n'
    '- Esta é uma análise preliminar e educativa, NÃO uma verificação '
    'farmacêutica definitiva. Português do Brasil.';

const String guidePrompt =
    'Explique o medicamento abaixo para um paciente leigo, em português do '
    'Brasil, com base em consenso clínico comum e bulas típicas.\n\n'
    'Responda APENAS com um JSON válido, sem nenhum texto antes ou depois, '
    'neste formato:\n'
    '{"whatFor":"...","howToUse":"...","commonSideEffects":["..."],'
    '"warnings":["..."],"note":"..."}\n\n'
    'Regras:\n'
    '- whatFor: para que serve, em 1-2 frases simples.\n'
    '- howToUse: como se toma normalmente (com/sem alimento, manhã/noite, '
    'quantidade usual); considere a dosagem informada, se houver; 1-2 frases.\n'
    '- commonSideEffects: de 3 a 6 efeitos colaterais comuns, itens curtos.\n'
    '- warnings: de 2 a 5 avisos importantes (o que evitar — álcool, outros '
    'remédios, leite —, quando procurar médico, gravidez/amamentação), itens '
    'curtos.\n'
    '- note: uma frase lembrando que são informações gerais e que a bula do '
    'fabricante e o médico/farmacêutico prevalecem.\n'
    '- Seja geral e seguro; não invente dados de fabricante, percentuais ou '
    'estudos.\n'
    '- Se o nome não corresponder a um medicamento real, devolva whatFor '
    '"Não foi possível identificar este medicamento.", os demais textos '
    'curtos e as listas vazias.';

const String schedulePrompt =
    'Você é um assistente que apenas apresenta opções de organização de '
    'horários para revisão humana. Você NÃO é médico nem farmacêutico e NÃO '
    'faz prescrição.\n\n'
    'Responda APENAS com JSON válido:\n'
    '{"summary":"...","suggestions":[{"medicationId":"...","medicationName":'
    '"...","suggestedTimes":["07:30"],"reason":"...","warnings":["..."]}]}\n\n'
    'Regras obrigatórias:\n'
    '- Nunca altere nem sugira alterar dose, quantidade de doses, frequência, '
    'duração ou intervalo prescrito. A tarefa é limitada ao horário do '
    'relógio.\n'
    '- Se a receita trouxer horários fixos, mantenha-os exatamente.\n'
    '- Se não houver dados suficientes para verificar que a mudança respeita '
    'a prescrição, mantenha os horários atuais e explique a limitação.\n'
    '- Não deduza horários clinicamente equivalentes, não invente intervalos '
    'e não presuma que horários podem ser movidos.\n'
    '- Não recomende iniciar, suspender, substituir, aumentar ou reduzir '
    'medicamentos.\n'
    '- Inclua um item por medicamento usando o medicationId exato. Se não '
    'houver mudança segura e justificável, devolva os horários atuais.\n'
    '- warnings deve explicitar qualquer informação ausente ou ponto que '
    'precise de confirmação profissional.\n'
    '- Português do Brasil, linguagem simples.';

const String questionsPrompt =
    'Você é um assistente que prepara pacientes para consultas médicas. Com '
    'base nos dados do paciente abaixo, sugira perguntas que ele deveria '
    'levar ao médico.\n\n'
    'Responda APENAS com um JSON válido, sem nenhum texto antes ou depois, '
    'neste formato:\n'
    '{"questions":["...","..."]}\n\n'
    'Regras:\n'
    '- De 3 a 5 perguntas, em português do Brasil, na ordem de importância.\n'
    '- Personalize usando os medicamentos, adesão e exames informados '
    '(ex.: "A losartana pode ser mantida com essa pressão em dia?").\n'
    '- Perguntas devem ser seguras para o paciente perguntar; nada de '
    'diagnosticar ou sugerir alterações de tratamento como se fosse certeza.\n'
    '- Sem dados relevantes, use perguntas gerais úteis de uma consulta de '
    'rotina.';

// ===== Sanitização (ports dos utils do PWA — nunca lançam) =====

/// Corta `value` em `max` caracteres depois de aparar; não-string vira ''.
String aiClipText(Object? value, int max) {
  final text = value is String ? value.trim() : '';
  if (text.length <= max) return text;
  return text.substring(0, max);
}

/// Lista de strings não vazias, aparadas, cortadas por item e por quantidade.
List<String> aiStringList(Object? raw, int maxItems, int maxLen) {
  if (raw is! List) return const [];
  final result = <String>[];
  for (final item in raw) {
    if (item is String && item.trim().isNotEmpty) {
      final trimmed = item.trim();
      result.add(
        trimmed.length <= maxLen ? trimmed : trimmed.substring(0, maxLen),
      );
      if (result.length >= maxItems) break;
    }
  }
  return result;
}

/// Extrai o primeiro objeto JSON da resposta do modelo, tolerante a blocos
/// de código e texto ao redor (mesma regra do `extractJson` do PWA).
Map<String, dynamic> aiExtractJson(String text) {
  final cleaned = text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
  final start = cleaned.indexOf('{');
  final end = cleaned.lastIndexOf('}');
  if (start == -1 || end <= start) {
    throw AiException(
      'A IA não devolveu os dados no formato esperado. Tente novamente.',
    );
  }
  try {
    final decoded = jsonDecode(cleaned.substring(start, end + 1));
    if (decoded is Map<String, dynamic>) return decoded;
    throw AiException(
      'A IA não devolveu os dados no formato esperado. Tente novamente.',
    );
  } on AiException {
    rethrow;
  } catch (_) {
    throw AiException(
      'A IA não devolveu os dados no formato esperado. Tente novamente.',
    );
  }
}

/// Normaliza a resposta da análise de interações; nunca lança — entrada
/// estranha vira relatório vazio (mesma regra do `sanitizeInteractionReport`).
AiInteractionReport sanitizeInteractionReport(Object? value) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};

  AiInteractionSeverity severityOf(Object? raw) {
    if (raw == 'alta') return AiInteractionSeverity.alta;
    if (raw == 'baixa') return AiInteractionSeverity.baixa;
    return AiInteractionSeverity.moderada;
  }

  final duplicates = <AiDuplicateGroup>[];
  final rawDuplicates = record['duplicates'];
  if (rawDuplicates is List) {
    for (final item in rawDuplicates) {
      if (item is! Map<String, dynamic>) continue;
      final ingredient = aiClipText(item['activeIngredient'], 150);
      final medications = aiStringList(item['medications'], 6, 120);
      if (ingredient.isEmpty || medications.isEmpty) continue;
      duplicates.add(
        AiDuplicateGroup(
          activeIngredient: ingredient,
          medications: medications,
          note: aiClipText(item['note'], 300),
        ),
      );
      if (duplicates.length >= 10) break;
    }
  }

  final interactions = <AiInteractionAlert>[];
  final rawInteractions = record['interactions'];
  if (rawInteractions is List) {
    for (final item in rawInteractions) {
      if (item is! Map<String, dynamic>) continue;
      final description = aiClipText(item['description'], 500);
      final medications = aiStringList(item['medications'], 6, 120);
      if (description.isEmpty || medications.isEmpty) continue;
      interactions.add(
        AiInteractionAlert(
          severity: severityOf(item['severity']),
          medications: medications,
          description: description,
          recommendation: aiClipText(item['recommendation'], 400),
        ),
      );
      if (interactions.length >= 10) break;
    }
  }

  final sources = <String>[];
  final rawSources = record['sources'];
  if (rawSources is List) {
    for (final item in rawSources) {
      if (item is! Map<String, dynamic>) continue;
      final name = aiClipText(item['name'], 180);
      if (name.isEmpty) continue;
      final date = aiClipText(item['date'], 40);
      sources.add(date.isEmpty ? name : '$name ($date)');
      if (sources.length >= 5) break;
    }
  }

  return AiInteractionReport(
    summary: aiClipText(record['summary'], 300),
    duplicates: duplicates,
    interactions: interactions,
    sources: sources,
  );
}

/// Normaliza a resposta da bula; nunca lança (mesma regra do PWA).
AiMedicationGuide sanitizeMedicationGuide(Object? value) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};
  return AiMedicationGuide(
    whatFor: aiClipText(record['whatFor'], 400),
    howToUse: aiClipText(record['howToUse'], 400),
    commonSideEffects: aiStringList(record['commonSideEffects'], 6, 120),
    warnings: aiStringList(record['warnings'], 6, 200),
    note: aiClipText(record['note'], 300),
  );
}

/// Perguntas da consulta: apenas strings não vazias, no máximo 8 itens.
List<String> sanitizeConsultationQuestions(Object? value) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};
  final raw = record['questions'];
  if (raw is! List) return const [];
  return raw
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(8)
      .map((item) => item.length <= 300 ? item : item.substring(0, 300))
      .toList();
}

/// Normaliza horário 'HH:MM' (hora com 1 dígito aceita); '' se inválido.
String aiCleanAdvisorTime(Object? value) {
  if (value is! String) return '';
  final match = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(value);
  if (match == null) return '';
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return '';
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

/// 'HH:MM' → minutos desde a meia-noite; null se inválido.
int? aiTimeToMinutes(String time) {
  final clean = aiCleanAdvisorTime(time);
  if (clean.isEmpty) return null;
  final parts = clean.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Menor intervalo entre doses de um dia em minutos, incluindo a virada da
/// meia-noite (última → primeira do dia seguinte) — o que importa para
/// esquemas tipo "8/8h".
int? aiMinGapMinutes(List<String> times) {
  final minutes =
      times.map(aiTimeToMinutes).whereType<int>().toList()..sort();
  if (minutes.length < 2) return null;
  var min = minutes[1] - minutes[0];
  for (var i = 1; i < minutes.length - 1; i++) {
    final gap = minutes[i + 1] - minutes[i];
    if (gap < min) min = gap;
  }
  final wrapGap = 24 * 60 - (minutes[minutes.length - 1] - minutes[0]);
  return min < wrapGap ? min : wrapGap;
}

bool _aiSameTimes(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final sortedA = [...a]..sort();
  final sortedB = [...b]..sort();
  for (var i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
  }
  return true;
}

/// Normalização de nomes para casar sugestões sem id (igual ao
/// `normalizeMedicationName` do PWA): minúsculas, sem acentos, sem pontuação.
String aiNormalizeMedicationName(String name) {
  const diacritics = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ï': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final lowered = name.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final char in lowered.runes) {
    final ch = String.fromCharCode(char);
    buffer.write(diacritics[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Normaliza a resposta do consultor de horários; nunca lança. Só entram
/// sugestões cujo medicationId (ou, por fallback, nome normalizado)
/// corresponde a um medicamento conhecido — a IA não pode criar nem
/// remover medicamentos por este caminho. Checagens determinísticas
/// (contagem de doses e intervalo mínimo) entram como warnings.
AiScheduleAdvice sanitizeScheduleAdvice(
  Object? value,
  List<AiScheduleMed> medications,
) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};

  final byId = {for (final med in medications) med.id: med};
  AiScheduleMed? findByName(String name) {
    final clean = aiNormalizeMedicationName(name);
    if (clean.isEmpty) return null;
    for (final med in medications) {
      if (aiNormalizeMedicationName(med.name) == clean) return med;
    }
    return null;
  }

  final suggestions = <AiScheduleSuggestion>[];
  final rawList = record['suggestions'];
  if (rawList is List) {
    for (final raw in rawList.take(15)) {
      if (raw is! Map<String, dynamic>) continue;
      final id = aiClipText(raw['medicationId'], 80);
      final name = aiClipText(raw['medicationName'], 120);
      final med = (id.isNotEmpty && byId.containsKey(id))
          ? byId[id]!
          : (name.isNotEmpty ? findByName(name) : null);
      if (med == null) continue;

      // Horários válidos, sem repetição, ordenados (máximo 8).
      final seen = <String>{};
      final rawTimes = raw['suggestedTimes'];
      if (rawTimes is List) {
        for (final item in rawTimes) {
          final clean = aiCleanAdvisorTime(item);
          if (clean.isNotEmpty) seen.add(clean);
          if (seen.length >= 8) break;
        }
      }
      final suggestedTimes = seen.toList()..sort();
      if (suggestedTimes.isEmpty) continue;

      final warnings = <String>[];
      final rawWarnings = raw['warnings'];
      if (rawWarnings is List) {
        for (final warning in rawWarnings) {
          if (warning is String && warning.trim().isNotEmpty) {
            final trimmed = warning.trim();
            warnings.add(
              trimmed.length <= 200 ? trimmed : trimmed.substring(0, 200),
            );
            if (warnings.length >= 4) break;
          }
        }
      }

      // Verificações determinísticas do app (não dependem do modelo):
      if (suggestedTimes.length != med.times.length) {
        warnings.insert(
          0,
          'A IA sugeriu ${suggestedTimes.length} dose(s), mas este '
          'tratamento tem ${med.times.length}. Confira antes de aplicar.',
        );
      }
      final gap = aiMinGapMinutes(suggestedTimes);
      if (gap != null && gap < 60) {
        final hours = gap ~/ 60;
        final minutes = (gap % 60).toString().padLeft(2, '0');
        warnings.add(
          'Intervalo mínimo entre doses de apenas ${hours}h$minutes — '
          'confirme o que foi prescrito.',
        );
      }

      suggestions.add(
        AiScheduleSuggestion(
          medicationId: med.id,
          medicationName: med.name,
          suggestedTimes: suggestedTimes,
          reason: aiClipText(raw['reason'], 400),
          warnings: warnings.toSet().toList(),
          changed: !_aiSameTimes(med.times, suggestedTimes),
          minGapMinutes: gap,
        ),
      );
      if (suggestions.length >= 15) break;
    }
  }

  return AiScheduleAdvice(
    summary: aiClipText(record['summary'], 400),
    suggestions: suggestions,
  );
}
