import 'dart:convert';

class Reminder {
  final String id;
  final String medicineName;
  final String dosage;
  final String presentation;
  final List<DateTime> times;
  bool taken;

  Reminder({
    required this.id,
    required this.medicineName,
    required this.dosage,
    required this.presentation,
    required this.times,
    this.taken = false,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      medicineName: json['medicineName'] as String,
      dosage: json['dosage'] as String,
      presentation: json['presentation'] as String,
      times: (json['times'] as List<dynamic>)
          .map((e) => DateTime.parse(e as String))
          .toList(),
      taken: json['taken'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineName': medicineName,
        'dosage': dosage,
        'presentation': presentation,
        'times': times.map((t) => t.toIso8601String()).toList(),
        'taken': taken,
      };

  bool isOnDay(DateTime day) {
    return times.any((t) =>
        t.year == day.year && t.month == day.month && t.day == day.day);
  }
}
