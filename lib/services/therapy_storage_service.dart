import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dose_event.dart';
import '../models/treatment.dart';

class TherapyStorageService {
  static const _treatmentsKey = 'treatments_db';
  static const _doseEventsKey = 'dose_events_db';

  Future<List<Treatment>> loadTreatments() async {
    final preferences = await SharedPreferences.getInstance();
    final data = preferences.getString(_treatmentsKey);
    if (data == null || data.isEmpty) return [];

    final decoded = jsonDecode(data) as List<dynamic>;
    return decoded
        .map((item) => Treatment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<DoseEvent>> loadDoseEvents() async {
    final preferences = await SharedPreferences.getInstance();
    final data = preferences.getString(_doseEventsKey);
    if (data == null || data.isEmpty) return [];

    final decoded = jsonDecode(data) as List<dynamic>;
    return decoded
        .map((item) => DoseEvent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveTreatments(List<Treatment> treatments) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _treatmentsKey,
      jsonEncode(treatments.map((treatment) => treatment.toJson()).toList()),
    );
  }

  Future<void> saveDoseEvents(List<DoseEvent> doseEvents) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _doseEventsKey,
      jsonEncode(doseEvents.map((event) => event.toJson()).toList()),
    );
  }
}
