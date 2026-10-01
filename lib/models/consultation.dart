import 'package:uuid/uuid.dart';

class ConsultationStatus {
  static const scheduled = 'scheduled';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static const List<String> values = [scheduled, completed, cancelled];

  static String label(String status) {
    switch (status) {
      case scheduled:
        return 'Agendada';
      case completed:
        return 'Realizada';
      case cancelled:
        return 'Cancelada';
      default:
        return status;
    }
  }
}

class Consultation {
  const Consultation({
    required this.id,
    required this.doctorId,
    required this.date,
    this.title = '',
    this.notes = '',
    this.status = ConsultationStatus.scheduled,
    this.returnDate,
    this.completedAt,
  });

  factory Consultation.create({
    required String doctorId,
    required DateTime date,
    String title = '',
    String notes = '',
    DateTime? returnDate,
    DateTime? completedAt,
  }) {
    return Consultation(
      id: const Uuid().v4(),
      doctorId: doctorId,
      date: date,
      title: title,
      notes: notes,
      status: ConsultationStatus.scheduled,
      returnDate: returnDate,
      completedAt: completedAt,
    );
  }

  final String id;
  final String doctorId;
  final DateTime date;
  final String title;
  final String notes;
  final String status;
  final DateTime? returnDate;
  final DateTime? completedAt;

  bool get isPast => date.isBefore(DateTime.now());
  bool get isFuture => !isPast;
  bool get isScheduled => status == ConsultationStatus.scheduled;
  bool get isCompleted => status == ConsultationStatus.completed;
  bool get isCancelled => status == ConsultationStatus.cancelled;

  String get statusLabel => ConsultationStatus.label(status);

  factory Consultation.fromJson(Map<String, dynamic> json) {
    return Consultation(
      id: json['id'] as String,
      doctorId: json['doctorId'] as String,
      date: DateTime.parse(json['date'] as String),
      title: json['title'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? ConsultationStatus.scheduled,
      returnDate: json['returnDate'] != null
          ? DateTime.parse(json['returnDate'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'doctorId': doctorId,
        'date': date.toIso8601String(),
        'title': title,
        'notes': notes,
        'status': status,
        'returnDate': returnDate?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  Consultation copyWith({
    String? doctorId,
    DateTime? date,
    String? title,
    String? notes,
    String? status,
    DateTime? returnDate,
    bool clearReturnDate = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    final newStatus = status ?? this.status;
    final newReturnDate =
        clearReturnDate ? null : (returnDate ?? this.returnDate);

    // returnDate is only meaningful when the consultation is completed.
    // Reverting to a non-completed status clears it.
    if (newStatus != ConsultationStatus.completed && newReturnDate != null) {
      throw ArgumentError(
        'returnDate can only be set on a completed consultation',
      );
    }
    if (newStatus != ConsultationStatus.completed) {
      // Reverting clears the return date automatically.
      return Consultation(
        id: id,
        doctorId: doctorId ?? this.doctorId,
        date: date ?? this.date,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        status: newStatus,
        returnDate: null,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      );
    }

    return Consultation(
      id: id,
      doctorId: doctorId ?? this.doctorId,
      date: date ?? this.date,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      status: newStatus,
      returnDate: newReturnDate,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}