enum DoseStatus { pending, taken, skipped }

class DoseEvent {
  final String id;
  final String treatmentId;
  final DateTime scheduledAt;
  final DoseStatus status;
  final DateTime? completedAt;

  const DoseEvent({
    required this.id,
    required this.treatmentId,
    required this.scheduledAt,
    this.status = DoseStatus.pending,
    this.completedAt,
  });

  factory DoseEvent.fromJson(Map<String, dynamic> json) {
    return DoseEvent(
      id: json['id'] as String,
      treatmentId: json['treatmentId'] as String,
      scheduledAt: DateTime.parse(json['scheduledAt'] as String),
      status: DoseStatus.values.byName(
        json['status'] as String? ?? DoseStatus.pending.name,
      ),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
    );
  }

  DoseEvent copyWith({DoseStatus? status, DateTime? completedAt}) {
    return DoseEvent(
      id: id,
      treatmentId: treatmentId,
      scheduledAt: scheduledAt,
      status: status ?? this.status,
      completedAt: completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'treatmentId': treatmentId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'status': status.name,
        'completedAt': completedAt?.toIso8601String(),
      };
}
