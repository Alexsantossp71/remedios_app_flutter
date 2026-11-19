/// Sanitização das respostas do modelo (ports dos utils do PWA). As
/// funções `sanitize*` nunca lançam: entrada estranha vira objeto vazio.
/// A exceção é `aiExtractJson`, que sinaliza resposta malformada com
/// [AiException] para a fachada converter em mensagem de usuário.
library;

import 'dart:convert';

import '../ai_proxy_client.dart';
import '../../data/medical_specialties.dart';
import '../../models/exam.dart';
import 'ai_models.dart';

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
  final cleaned = text.replaceAll(
    RegExp(r'```(?:json)?', caseSensitive: false),
    '',
  );
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
  final minutes = times.map(aiTimeToMinutes).whereType<int>().toList()..sort();
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
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ï': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
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

/// Normaliza a resposta da leitura do pedido; nunca lança — entrada
/// estranha vira campos vazios. Categoria fora da lista fixa e data fora
/// do formato AAAA-MM-DD são descartadas (a IA não decide o cadastro).
AiExamScan sanitizeExamScan(Object? value) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};

  final category = aiClipText(record['category'], 40);
  final date = aiClipText(record['date'], 10);

  return AiExamScan(
    name: aiClipText(record['name'], 200),
    category: examCategories.contains(category) ? category : '',
    doctorName: aiClipText(record['doctorName'], 120),
    place: aiClipText(record['place'], 120),
    date: RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ? date : '',
  );
}

/// Normaliza a resposta da extração; nunca lança — entrada estranha vira
/// campos vazios. UF fora da lista do Brasil e especialidade fora da
/// lista fixa do cadastro são descartadas (a IA não decide o cadastro).
DoctorAiData sanitizeDoctorData(Object? value) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};

  final crm = aiClipText(record['crm'], 12).replaceAll(RegExp(r'\D'), '');
  final uf = aiClipText(record['uf'], 2).trim().toUpperCase();
  final specialty = matchFixedSpecialty(
    aiClipText(record['especialidade'], 80),
  );

  return DoctorAiData(
    name: _cleanAiDoctorName(aiClipText(record['nome'], 120)),
    specialty: specialty,
    crm: crm,
    crmState: isValidBrazilianUf(uf) ? uf : '',
    phone: aiClipText(record['telefone'], 30).trim(),
  );
}

/// Casa o texto da IA com a lista fixa do cadastro: primeiro igualdade
/// exata (sem maiúsculas), depois um contém o outro. Sem casamento, vazio
/// — o usuário escolhe na lista. Também usada pelo retorno do conselho
/// (CREMESP) para manter o cadastro dentro da lista fixa.
String matchFixedSpecialty(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final needle = value.toLowerCase();
  for (final specialty in kMedicalSpecialties) {
    if (specialty.toLowerCase() == needle) return specialty;
  }
  for (final specialty in kMedicalSpecialties) {
    final haystack = specialty.toLowerCase();
    if (haystack.contains(needle) || needle.contains(haystack)) {
      return specialty;
    }
  }
  return '';
}

/// Tira o prefixo Dr./Dra. e espaços duplicados (mesma convenção do
/// rascunho lido da receita).
String _cleanAiDoctorName(String raw) {
  var value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  value = value.replaceFirst(RegExp(r'^dra?\.?\s*', caseSensitive: false), '');
  return value.trim();
}
