import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/consultation.dart';
import '../services/consultation_storage_service.dart';

class ConsultationProvider extends ChangeNotifier {
  ConsultationProvider({ConsultationStorageService? storage})
      : _storage = storage ?? ConsultationStorageService();

  final ConsultationStorageService _storage;

  List<Consultation> _consultations = [];
  bool _isLoading = true;

  UnmodifiableListView<Consultation> get consultations =>
      UnmodifiableListView(_consultations);
  bool get isLoading => _isLoading;

  List<Consultation> get upcomingConsultations {
    final now = DateTime.now();
    return _consultations
        .where((c) =>
            c.status == ConsultationStatus.scheduled &&
            (c.date.isAfter(now) ||
                (c.date.year == now.year &&
                    c.date.month == now.month &&
                    c.date.day == now.day)))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Consultation> get pastConsultations {
    final now = DateTime.now();
    return _consultations
        .where((c) =>
            c.status != ConsultationStatus.scheduled ||
            (c.date.isBefore(now) &&
                !(c.date.year == now.year &&
                    c.date.month == now.month &&
                    c.date.day == now.day)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> initialize() async {
    _consultations = await _storage.loadConsultations();
    _sortConsultations();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveConsultation(Consultation consultation) async {
    final existingIndex =
        _consultations.indexWhere((item) => item.id == consultation.id);
    if (existingIndex == -1) {
      _consultations = [..._consultations, consultation];
    } else {
      _consultations = [
        for (var index = 0; index < _consultations.length; index++)
          if (index == existingIndex)
            consultation
          else
            _consultations[index],
      ];
    }
    _sortConsultations();
    await _storage.saveConsultation(consultation);
    notifyListeners();
  }

  Future<void> removeConsultation(String id) async {
    _consultations =
        _consultations.where((consultation) => consultation.id != id).toList();
    await _storage.deleteConsultation(id);
    notifyListeners();
  }

  Future<void> markAsCompleted(String id) async {
    final index = _consultations.indexWhere((c) => c.id == id);
    if (index != -1) {
      final updated = _consultations[index]
          .copyWith(status: ConsultationStatus.completed);
      await saveConsultation(updated);
    }
  }

  Future<void> markAsCancelled(String id) async {
    final index = _consultations.indexWhere((c) => c.id == id);
    if (index != -1) {
      final updated = _consultations[index]
          .copyWith(status: ConsultationStatus.cancelled);
      await saveConsultation(updated);
    }
  }

  List<Consultation> getConsultationsForDoctor(String doctorId) {
    return _consultations
        .where((c) => c.doctorId == doctorId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<Consultation> getConsultationsForDay(DateTime date) {
    return _consultations
        .where((c) =>
            c.date.year == date.year &&
            c.date.month == date.month &&
            c.date.day == date.day)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Consultas visibles desde [day] en adelante: ese día se muestran todas
  /// las del día (cualquier estado) y, para fechas futuras, las agendadas.
  List<Consultation> getConsultationsFromDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return _consultations
        .where((c) {
          if (c.date.isBefore(start)) return false;
          final isSameDay = c.date.year == day.year &&
              c.date.month == day.month &&
              c.date.day == day.day;
          return isSameDay || c.status == ConsultationStatus.scheduled;
        }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  void _sortConsultations() {
    _consultations.sort((a, b) => a.date.compareTo(b.date));
  }
}