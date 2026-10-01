import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/doctor.dart';
import '../services/doctor_storage_service.dart';

class DoctorProvider extends ChangeNotifier {
  DoctorProvider({DoctorStorageService? storage})
      : _storage = storage ?? DoctorStorageService();

  final DoctorStorageService _storage;

  List<Doctor> _doctors = [];
  bool _isLoading = true;

  UnmodifiableListView<Doctor> get doctors => UnmodifiableListView(_doctors);
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _doctors = await _storage.loadDoctors();
    _doctors.sort((first, second) =>
        first.name.toLowerCase().compareTo(second.name.toLowerCase()));
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveDoctor(Doctor doctor) async {
    final existingIndex = _doctors.indexWhere((item) => item.id == doctor.id);
    if (existingIndex == -1) {
      _doctors = [..._doctors, doctor];
    } else {
      _doctors = [
        for (var index = 0; index < _doctors.length; index++)
          if (index == existingIndex) doctor else _doctors[index],
      ];
    }
    _sortDoctors();
    await _storage.saveDoctor(doctor);
    notifyListeners();
  }

  Future<void> removeDoctor(String id) async {
    _doctors = _doctors.where((doctor) => doctor.id != id).toList();
    await _storage.deleteDoctor(id);
    notifyListeners();
  }

  List<Doctor> search(String query, {String specialty = ''}) {
    final normalizedQuery = query.trim().toLowerCase();
    return _doctors.where((doctor) {
      final matchesSpecialty =
          specialty.isEmpty || doctor.specialty == specialty;
      if (!matchesSpecialty) return false;
      if (normalizedQuery.isEmpty) return true;

      final searchableText = [
        doctor.name,
        doctor.specialty,
        doctor.crm,
        doctor.crmState,
        doctor.phone,
        doctor.email,
        doctor.clinic,
        doctor.fullAddress,
        doctor.healthPlans,
        doctor.notes,
      ].join(' ').toLowerCase();
      return searchableText.contains(normalizedQuery);
    }).toList();
  }

  void _sortDoctors() {
    _doctors.sort((first, second) =>
        first.name.toLowerCase().compareTo(second.name.toLowerCase()));
  }
}
