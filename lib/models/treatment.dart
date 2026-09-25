enum TreatmentFrequency { daily, weekdays, everyOtherDay }

class DoseTime {
  final int hour;
  final int minute;

  const DoseTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  factory DoseTime.fromJson(Map<String, dynamic> json) {
    return DoseTime(
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  int get minutesSinceMidnight => (hour * 60) + minute;
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
  final int? stock;
  final int? refillThreshold;
  final bool isArchived;

  const Treatment({
    required this.id,
    required this.name,
    required this.dosage,
    required this.presentation,
    required this.instructions,
    required this.startDate,
    required this.endDate,
    required this.frequency,
    required this.doseTimes,
    required this.stock,
    required this.refillThreshold,
    this.isArchived = false,
  });

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
      stock: json['stock'] as int?,
      refillThreshold: json['refillThreshold'] as int?,
      isArchived: json['isArchived'] as bool? ?? false,
    );
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
    int? stock,
    bool clearStock = false,
    int? refillThreshold,
    bool clearRefillThreshold = false,
    bool? isArchived,
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
      stock: clearStock ? null : stock ?? this.stock,
      refillThreshold: clearRefillThreshold
          ? null
          : refillThreshold ?? this.refillThreshold,
      isArchived: isArchived ?? this.isArchived,
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
        'stock': stock,
        'refillThreshold': refillThreshold,
        'isArchived': isArchived,
      };

  bool isScheduledOn(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
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
    }
  }

  bool get needsRefill =>
      stock != null && refillThreshold != null && stock! <= refillThreshold!;
}
