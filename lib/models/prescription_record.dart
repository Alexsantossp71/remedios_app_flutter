import 'treatment.dart';

/// Origem do registro de receita — de onde veio a informação de quem
/// receitou. Exibido no histórico para o usuário entender o contexto.
enum PrescriptionSource {
  /// Digitado à mão no formulário de tratamento.
  manual,

  /// Lido da foto da receita (OCR) e confirmado pelo usuário.
  prescriptionPhoto;

  String get label => switch (this) {
        PrescriptionSource.manual => 'Cadastro manual',
        PrescriptionSource.prescriptionPhoto => 'Foto da receita',
      };

  static PrescriptionSource fromName(String? name) =>
      PrescriptionSource.values.firstWhere(
        (source) => source.name == name,
        orElse: () => PrescriptionSource.manual,
      );
}

/// Um registro de "quem receitou e em que dia" no histórico de um
/// tratamento. Cada renovação de receita (médio ou data diferente ao
/// editar) cria um novo registro — nada é sobrescrito, o histórico é a
/// memória do usuário.
///
/// Nome e CRM são snapshot de exibição: o registro sobrevive a um médico
/// apagado do catálogo ([doctorId] pode ficar órfão sem quebrar nada).
class PrescriptionRecord {
  // Sem const de propósito: os registros nascem em runtime (DateTime.now)
  // e o assert de isNotEmpty não é expressão constante.
  PrescriptionRecord({
    required this.id,
    required this.treatmentId,
    this.doctorId,
    required this.doctorName,
    this.doctorCrm = '',
    this.doctorCrmState = '',
    required this.prescribedOn,
    this.source = PrescriptionSource.manual,
    required this.createdAt,
  }) : assert(id.isNotEmpty, 'id must not be empty'),
       assert(treatmentId.isNotEmpty, 'treatmentId must not be empty'),
       assert(doctorName.isNotEmpty, 'doctorName must not be empty');

  final String id;

  /// Tratamento dono do registro.
  final String treatmentId;

  /// Médico do catálogo vinculado, quando existir.
  final String? doctorId;

  /// Snapshot de exibição: nome do médico que assinou a receita.
  final String doctorName;

  /// Snapshot de exibição: CRM numérico (sem "CRM" e sem UF).
  final String doctorCrm;
  final String doctorCrmState;

  /// Data da receita — "em que dia" o médico prescreveu.
  final DateTime prescribedOn;

  final PrescriptionSource source;

  /// Quando o registro foi criado no app (auditoria, ordem do histórico).
  final DateTime createdAt;

  /// Rótulo de CRM igual ao do catálogo (Doctor.crmLabel): "CRM 123456/SP".
  String get crmLabel => [
        if (doctorCrm.trim().isNotEmpty) 'CRM ${doctorCrm.trim()}',
        if (doctorCrmState.trim().isNotEmpty)
          doctorCrmState.trim().toUpperCase(),
      ].join('/');

  factory PrescriptionRecord.fromJson(Map<String, dynamic> json) {
    return PrescriptionRecord(
      id: json['id'] as String,
      treatmentId: json['treatmentId'] as String,
      doctorId: json['doctorId'] as String?,
      doctorName: json['doctorName'] as String? ?? '',
      doctorCrm: json['doctorCrm'] as String? ?? '',
      doctorCrmState: json['doctorCrmState'] as String? ?? '',
      prescribedOn: DateTime.parse(json['prescribedOn'] as String),
      source: PrescriptionSource.fromName(json['source'] as String?),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'treatmentId': treatmentId,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'doctorCrm': doctorCrm,
        'doctorCrmState': doctorCrmState,
        'prescribedOn': prescribedOn.toIso8601String(),
        'source': source.name,
        'createdAt': createdAt.toIso8601String(),
      };

  /// O registro corresponde à receita atual do tratamento? (mesma
  /// identidade de prescritor e data) — usado para não duplicar registros
  /// quando o usuário salva sem mudar nada.
  bool matchesTreatment(Treatment treatment) =>
      doctorName.trim().toLowerCase() ==
          treatment.prescriberName.trim().toLowerCase() &&
      doctorCrm.trim() == treatment.prescriberCrm.trim() &&
      doctorCrmState.trim().toUpperCase() ==
          treatment.prescriberCrmState.trim().toUpperCase() &&
      _sameDay(prescribedOn, treatment.prescribedOn);

  static bool _sameDay(DateTime first, DateTime? second) {
    if (second == null) return false;
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}
