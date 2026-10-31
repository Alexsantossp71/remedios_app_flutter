import 'treatment.dart';

/// Rascunho de tratamento vindo de uma leitura automática (receita por OCR).
///
/// Preencher não é salvar: o rascunho só alimenta o formulário de tratamento,
/// que mantém a validação e a conferência do usuário como última palavra.
class TreatmentDraft {
  const TreatmentDraft({
    this.name = '',
    this.dosage = '',
    this.presentation = '',
    this.instructions = '',
    this.doseTimes = const [],
    this.endDate,
    this.frequency,
  });

  final String name;
  final String dosage;
  final String presentation;
  final String instructions;
  final List<DoseTime> doseTimes;
  final DateTime? endDate;

  /// Frequência lida da receita ("dia sim, dia não" vira
  /// [TreatmentFrequency.everyOtherDay]). Nulo = receita não disse nada e o
  /// formulário fica no padrão diário — ausência de informação não é inferência.
  final TreatmentFrequency? frequency;
}
