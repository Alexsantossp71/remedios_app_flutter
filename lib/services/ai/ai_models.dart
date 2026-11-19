/// Modelos de resultado das ferramentas de IA do PWA "Remédio na Hora"
/// (espelhos dos tipos do PWA) e o conversor Treatment -> AiScheduleMed.
/// Tipos de dados puros: nada aqui chama rede nem depende do proxy. A
/// sanitização das respostas vive em `ai_sanitizers.dart` e os prompts em
/// `ai_prompts.dart`.
library;

import '../../models/treatment.dart';

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

/// Campos reconhecidos na foto do pedido de exame; todos opcionais —
/// o usuário completa o que faltar no formulário.
class AiExamScan {
  const AiExamScan({
    required this.name,
    required this.category,
    required this.doctorName,
    required this.place,
    required this.date,
  });

  /// Nome(s) do(s) exame(s), separados por vírgula.
  final String name;

  /// Uma das [examCategories] ou '' quando não classificado.
  final String category;
  final String doctorName;
  final String place;

  /// 'AAAA-MM-DD' ou '' quando ilegível/ausente.
  final String date;
}

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
  const AiScheduleAdvice({required this.summary, required this.suggestions});

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
      const labels = [
        'segunda',
        'terça',
        'quarta',
        'quinta',
        'sexta',
        'sábado',
        'domingo',
      ];
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
        .map(
          (time) =>
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        )
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
    final instructions = med.instructions.isEmpty
        ? 'nenhuma'
        : med.instructions;
    final times = med.times.isNotEmpty ? med.times.join(', ') : 'nenhum';
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

/// Dados do médico extraídos de texto livre pela IA. Todos opcionais —
/// quem preenche e salva é o usuário; a IA só sugere o preenchimento.
class DoctorAiData {
  const DoctorAiData({
    this.name = '',
    this.specialty = '',
    this.crm = '',
    this.crmState = '',
    this.phone = '',
  });

  /// Nome sem o prefixo Dr./Dra. (mesma convenção do rascunho da receita).
  final String name;

  /// Só se casou com a lista fixa de especialidades do cadastro.
  final String specialty;

  /// Só dígitos.
  final String crm;

  /// UF válida do Brasil ("SP") ou vazio.
  final String crmState;

  final String phone;

  bool get isEmpty =>
      name.trim().isEmpty &&
      crm.trim().isEmpty &&
      specialty.trim().isEmpty &&
      phone.trim().isEmpty;
}
