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
  });

  final String name;
  final String dosage;
  final String presentation;
  final String instructions;
  final List<DoseTime> doseTimes;
  final DateTime? endDate;
}
