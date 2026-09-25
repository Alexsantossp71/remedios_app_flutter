import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/dose_event.dart';
import '../models/treatment.dart';
import '../services/therapy_storage_service.dart';

class TherapyProvider extends ChangeNotifier {
  TherapyProvider({TherapyStorageService? storage})
      : _storage = storage ?? TherapyStorageService();

  final TherapyStorageService _storage;
  final Uuid _uuid = const Uuid();

  List<Treatment> _treatments = [];
  List<DoseEvent> _doseEvents = [];
  bool _isLoading = true;

  UnmodifiableListView<Treatment> get treatments =>
      UnmodifiableListView(_treatments);
  UnmodifiableListView<Treatment> get activeTreatments =>
      UnmodifiableListView(_treatments.where((treatment) => !treatment.isArchived));
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _treatments = await _storage.loadTreatments();
    _doseEvents = await _storage.loadDoseEvents();
    await ensureDoseEventsFor(DateTime.now(), notify: false);

    _isLoading = false;
    notifyListeners();
  }

  List<DoseEvent> doseEventsForDay(DateTime date) {
    final day = _dateOnly(date);
    final events = _doseEvents.where((event) => _isSameDay(event.scheduledAt, day)).toList()
      ..sort((first, second) => first.scheduledAt.compareTo(second.scheduledAt));
    return events;
  }

  Treatment? treatmentById(String treatmentId) {
    for (final treatment in _treatments) {
      if (treatment.id == treatmentId) return treatment;
    }
    return null;
  }

  Future<void> addTreatment(Treatment treatment) async {
    _treatments = [..._treatments, treatment];
    await _storage.saveTreatments(_treatments);
    await ensureDoseEventsFor(DateTime.now(), notify: false);
    notifyListeners();
  }

  Future<void> updateTreatment(Treatment treatment) async {
    _treatments = _treatments
        .map((current) => current.id == treatment.id ? treatment : current)
        .toList();
    await _storage.saveTreatments(_treatments);
    await ensureDoseEventsFor(DateTime.now(), notify: false);
    notifyListeners();
  }

  Future<void> archiveTreatment(String treatmentId) async {
    final treatment = treatmentById(treatmentId);
    if (treatment == null) return;
    await updateTreatment(treatment.copyWith(isArchived: true));
  }

  Future<void> ensureDoseEventsFor(DateTime date, {bool notify = true}) async {
    final day = _dateOnly(date);
    final eventsToAdd = <DoseEvent>[];

    for (final treatment in activeTreatments) {
      if (!treatment.isScheduledOn(day)) continue;
      for (final doseTime in treatment.doseTimes) {
        final scheduledAt = DateTime(
          day.year,
          day.month,
          day.day,
          doseTime.hour,
          doseTime.minute,
        );
        final alreadyExists = _doseEvents.any(
          (event) =>
              event.treatmentId == treatment.id &&
              event.scheduledAt.isAtSameMomentAs(scheduledAt),
        );
        if (!alreadyExists) {
          eventsToAdd.add(
            DoseEvent(
              id: _uuid.v4(),
              treatmentId: treatment.id,
              scheduledAt: scheduledAt,
            ),
          );
        }
      }
    }

    if (eventsToAdd.isEmpty) return;
    _doseEvents = [..._doseEvents, ...eventsToAdd];
    await _storage.saveDoseEvents(_doseEvents);
    if (notify) notifyListeners();
  }

  Future<void> setDoseStatus(DoseEvent doseEvent, DoseStatus status) async {
    if (doseEvent.status == status) return;

    final treatment = treatmentById(doseEvent.treatmentId);
    if (treatment == null) return;

    var updatedTreatment = treatment;
    if (treatment.stock != null) {
      if (doseEvent.status != DoseStatus.taken && status == DoseStatus.taken) {
        updatedTreatment = treatment.copyWith(
          stock: treatment.stock! > 0 ? treatment.stock! - 1 : 0,
        );
      } else if (doseEvent.status == DoseStatus.taken && status != DoseStatus.taken) {
        updatedTreatment = treatment.copyWith(stock: treatment.stock! + 1);
      }
    }

    final updatedEvent = doseEvent.copyWith(
      status: status,
      completedAt: status == DoseStatus.pending ? null : DateTime.now(),
    );
    _doseEvents = _doseEvents
        .map((event) => event.id == updatedEvent.id ? updatedEvent : event)
        .toList();
    _treatments = _treatments
        .map((current) => current.id == updatedTreatment.id ? updatedTreatment : current)
        .toList();

    await Future.wait([
      _storage.saveDoseEvents(_doseEvents),
      _storage.saveTreatments(_treatments),
    ]);
    notifyListeners();
  }

  DayAdherence adherenceForDay(DateTime date) {
    final events = doseEventsForDay(date);
    final completed = events.where((event) => event.status != DoseStatus.pending).length;
    final taken = events.where((event) => event.status == DoseStatus.taken).length;
    return DayAdherence(total: events.length, completed: completed, taken: taken);
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

class DayAdherence {
  const DayAdherence({
    required this.total,
    required this.completed,
    required this.taken,
  });

  final int total;
  final int completed;
  final int taken;

  double get completionRate => total == 0 ? 0 : completed / total;
  double get adherenceRate => total == 0 ? 0 : taken / total;
}
