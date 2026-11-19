enum TreatmentFrequency { daily, weekdays, everyOtherDay, weekly }

class DoseTime {
  final int hour;
  final int minute;

  const DoseTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  factory DoseTime.fromJson(Map<String, dynamic> json) {
    return DoseTime(hour: json['hour'] as int, minute: json['minute'] as int);
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  int get minutesSinceMidnight => (hour * 60) + minute;

  /// Valor, não identidade: "08:00" gerado pelo preset e "08:00" vindo do
  /// JSON são o mesmo horário — sem isto, expect(times, [DoseTime(...)])
  /// falha e dedup por igualdade nunca acontece.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoseTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      'DoseTime(${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')})';
}

class Treatment {
  final String id;
  final String name;
  final String dosage;
  final String presentation;
  final String instructions;
  final DateTime startDate;
  final DateTime? endDate;
  final TreatmentFrequency frequency;
  final List<DoseTime> doseTimes;

  /// Dias da semana em que a dose é tomada quando a frequência é
  /// [TreatmentFrequency.weekly] — [DateTime.weekday]: 1 = segunda …
  /// 7 = domingo. Vazio nos outros casos (e enquanto o usuário não escolhe
  /// no formulário: [isScheduledOn] devolve falso, nada é agendado às cegas).
  final List<int> weekdays;

  final int? stock;
  final int? refillThreshold;
  final bool isArchived;

  /// Quem receitou — snapshot de exibição do registro de receita atual.
  /// [prescriberDoctorId] aponta para o catálogo de médicos quando o médico
  /// foi vinculado; nome/CRM ficam gravados junto para o registro sobreviver
  /// a um médico apagado do catálogo. [prescribedOn] é a data da receita.
  final String? prescriberDoctorId;
  final String prescriberName;
  final String prescriberCrm;
  final String prescriberCrmState;
  final DateTime? prescribedOn;

  Treatment({
    required this.id,
    required this.name,
    required this.dosage,
    required this.presentation,
    required this.instructions,
    required this.startDate,
    required this.endDate,
    required this.frequency,
    required this.doseTimes,
    this.weekdays = const [],
    required this.stock,
    required this.refillThreshold,
    this.isArchived = false,
    this.prescriberDoctorId,
    this.prescriberName = '',
    this.prescriberCrm = '',
    this.prescriberCrmState = '',
    this.prescribedOn,
  }) : assert(id.isNotEmpty, 'id must not be empty'),
       assert(name.isNotEmpty, 'name must not be empty'),
       assert(dosage.isNotEmpty, 'dosage must not be empty'),
       assert(presentation.isNotEmpty, 'presentation must not be empty'),
       assert(doseTimes.isNotEmpty, 'DoseTimes cannot be empty'),
       assert(
         weekdays.every((day) => day >= 1 && day <= 7),
         'weekdays must be DateTime.weekday values (1=Mon … 7=Sun)',
       ),
       assert(stock == null || stock >= 0, 'stock must be non-negative'),
       assert(
         refillThreshold == null || refillThreshold >= 0,
         'refillThreshold must be non-negative',
       ),
       assert(
         endDate == null ||
             startDate.isBefore(endDate) ||
             startDate.isAtSameMomentAs(endDate),
         'startDate must be before or equal to endDate',
       );

  factory Treatment.fromJson(Map<String, dynamic> json) {
    return Treatment(
      id: json['id'] as String,
      name: json['name'] as String,
      dosage: json['dosage'] as String? ?? '',
      presentation: json['presentation'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      frequency: TreatmentFrequency.values.byName(
        json['frequency'] as String? ?? TreatmentFrequency.daily.name,
      ),
      doseTimes: (json['doseTimes'] as List<dynamic>? ?? const [])
          .map((item) => DoseTime.fromJson(item as Map<String, dynamic>))
          .toList(),
      weekdays: (json['weekdays'] as List<dynamic>? ?? const [])
          .map((item) => item as int)
          .toList(),
      stock: json['stock'] as int?,
      refillThreshold: json['refillThreshold'] as int?,
      isArchived: json['isArchived'] as bool? ?? false,
      prescriberDoctorId: json['prescriberDoctorId'] as String?,
      prescriberName: json['prescriberName'] as String? ?? '',
      prescriberCrm: json['prescriberCrm'] as String? ?? '',
      prescriberCrmState: json['prescriberCrmState'] as String? ?? '',
      prescribedOn: json['prescribedOn'] == null
          ? null
          : DateTime.parse(json['prescribedOn'] as String),
    );
  }

  /// Há registro de receita? Nome OU vínculo com médico do catálogo.
  bool get hasPrescriber =>
      prescriberName.trim().isNotEmpty ||
      (prescriberDoctorId?.trim().isNotEmpty ?? false);

  /// Rótulo de CRM igual ao do catálogo (Doctor.crmLabel): "CRM 123456/SP".
  String get prescriberCrmLabel => [
    if (prescriberCrm.trim().isNotEmpty) 'CRM ${prescriberCrm.trim()}',
    if (prescriberCrmState.trim().isNotEmpty)
      prescriberCrmState.trim().toUpperCase(),
  ].join('/');

  /// Comparação de identidade do prescritor entre duas versões do
  /// tratamento — muda nome, CRM ou data da receita => renovação nova.
  static bool samePrescription(Treatment first, Treatment second) =>
      first.prescriberName.trim().toLowerCase() ==
          second.prescriberName.trim().toLowerCase() &&
      first.prescriberCrm.trim() == second.prescriberCrm.trim() &&
      _sameDay(first.prescribedOn, second.prescribedOn);

  static bool _sameDay(DateTime? first, DateTime? second) {
    if (first == null || second == null) return first == second;
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  Treatment copyWith({
    String? name,
    String? dosage,
    String? presentation,
    String? instructions,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    TreatmentFrequency? frequency,
    List<DoseTime>? doseTimes,
    List<int>? weekdays,
    int? stock,
    bool clearStock = false,
    int? refillThreshold,
    bool clearRefillThreshold = false,
    bool? isArchived,
    String? prescriberDoctorId,
    bool clearPrescriberDoctorId = false,
    String? prescriberName,
    bool clearPrescriber = false,
    String? prescriberCrm,
    String? prescriberCrmState,
    DateTime? prescribedOn,
    bool clearPrescribedOn = false,
  }) {
    return Treatment(
      id: id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      presentation: presentation ?? this.presentation,
      instructions: instructions ?? this.instructions,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      frequency: frequency ?? this.frequency,
      doseTimes: doseTimes ?? this.doseTimes,
      weekdays: weekdays ?? this.weekdays,
      stock: clearStock ? null : stock ?? this.stock,
      refillThreshold: clearRefillThreshold
          ? null
          : refillThreshold ?? this.refillThreshold,
      isArchived: isArchived ?? this.isArchived,
      // clearPrescriber apaga o registro inteiro (vínculo + snapshot):
      // "sem receita" é um estado, não três campos soltos.
      prescriberDoctorId: clearPrescriber || clearPrescriberDoctorId
          ? null
          : prescriberDoctorId ?? this.prescriberDoctorId,
      prescriberName: clearPrescriber
          ? ''
          : prescriberName ?? this.prescriberName,
      prescriberCrm: clearPrescriber ? '' : prescriberCrm ?? this.prescriberCrm,
      prescriberCrmState: clearPrescriber
          ? ''
          : prescriberCrmState ?? this.prescriberCrmState,
      prescribedOn: clearPrescribedOn
          ? null
          : prescribedOn ?? this.prescribedOn,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dosage': dosage,
    'presentation': presentation,
    'instructions': instructions,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'frequency': frequency.name,
    'doseTimes': doseTimes.map((time) => time.toJson()).toList(),
    'weekdays': weekdays,
    'stock': stock,
    'refillThreshold': refillThreshold,
    'isArchived': isArchived,
    'prescriberDoctorId': prescriberDoctorId,
    'prescriberName': prescriberName,
    'prescriberCrm': prescriberCrm,
    'prescriberCrmState': prescriberCrmState,
    'prescribedOn': prescribedOn?.toIso8601String(),
  };

  bool isScheduledOn(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEnd = endDate == null
        ? null
        : DateTime(endDate!.year, endDate!.month, endDate!.day);

    if (isArchived || normalizedDate.isBefore(normalizedStart)) return false;
    if (normalizedEnd != null && normalizedDate.isAfter(normalizedEnd)) {
      return false;
    }

    switch (frequency) {
      case TreatmentFrequency.daily:
        return true;
      case TreatmentFrequency.weekdays:
        return normalizedDate.weekday <= DateTime.friday;
      case TreatmentFrequency.everyOtherDay:
        return normalizedDate.difference(normalizedStart).inDays.isEven;
      case TreatmentFrequency.weekly:
        // Sem dia escolhido, sem dose: a conferência decide antes de salvar.
        return weekdays.contains(normalizedDate.weekday);
    }
  }

  bool get needsRefill =>
      stock != null && refillThreshold != null && stock! <= refillThreshold!;
}
