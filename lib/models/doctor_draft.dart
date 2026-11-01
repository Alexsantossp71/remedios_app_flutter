/// Rascunho de médico lido da foto da receita (OCR).
///
/// Segue o mesmo padrão do [TreatmentDraft]: preenche o formulário de um
/// médico NOVO para conferência humana — a leitura só preenche, quem salva
/// é o usuário. Nunca usado quando existe `initialDoctor` (edição).
class DoctorDraft {
  const DoctorDraft({
    this.name = '',
    this.crm = '',
    this.crmState = '',
  });

  /// Nome sem prefixo Dr./Dra., como veio da receita.
  final String name;

  /// Só dígitos.
  final String crm;

  /// Duas letras ("SP") ou vazio.
  final String crmState;

  bool get isEmpty => name.trim().isEmpty && crm.trim().isEmpty;
}
