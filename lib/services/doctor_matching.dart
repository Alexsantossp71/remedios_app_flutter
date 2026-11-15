import '../models/doctor.dart';

/// Casamento de médicos lidos (OCR/IA/registro antigo) com o catálogo.
///
/// Regra compartilhada por "quem receitou" (tratamento), pedido de exame e
/// foto da receita para cadastro de médico: o mesmo médico não vira dois
/// cadastros por diferença de caixa ou espaço — mas CRM divergente não vira
/// "atualização silenciosa" de outro médico, vira registro novo conferido.
Doctor? findDoctorInCatalog(
  Iterable<Doctor> doctors, {
  required String name,
  String crm = '',
  String crmState = '',
}) {
  final crmDigits = crm.trim();
  final uf = crmState.trim().toUpperCase();

  // 1. CRM + UF iguais: identificação forte — sobrevive a nome ruidoso de
  //    OCR ("Dr, Joao Silva" não impede quem o CRM já confirma).
  if (crmDigits.isNotEmpty && uf.isNotEmpty) {
    for (final doctor in doctors) {
      if (doctor.crm.trim() == crmDigits &&
          doctor.crmState.trim().toUpperCase() == uf) {
        return doctor;
      }
    }
  }

  // 2. Nome normalizado: caixa/espaços ignorados. CRM divergente (os dois
  //    preenchidos e diferentes) impede o casamento — nova conferência,
  //    não troca silenciosa. CRM VAZIO no catálogo é "desconhecido", não
  //    divergente: o nome confirma quem é e o número lido enriquece o
  //    registro da receita sem duplicar o médico.
  final lowered = normalizePersonName(name);
  if (lowered.isEmpty) return null;
  for (final doctor in doctors) {
    if (normalizePersonName(doctor.name) != lowered) continue;
    final doctorCrm = doctor.crm.trim();
    if (crmDigits.isEmpty || doctorCrm.isEmpty || doctorCrm == crmDigits) {
      return doctor;
    }
  }
  return null;
}

/// Nome pronto para casamento: sem espaços das pontas, caixa baixa e
/// espaços internos colapsados ("  joão   silva " == "João Silva").
String normalizePersonName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
