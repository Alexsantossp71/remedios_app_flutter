import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/health_plan.dart';
import '../services/health_plan_storage_service.dart';

/// Provider for managing health plans state.
/// Follows the same pattern as DoctorProvider and TherapyProvider.
class HealthPlanProvider extends ChangeNotifier {
  HealthPlanProvider({HealthPlanStorageService? storage})
      : _storage = storage ?? HealthPlanStorageService();

  final HealthPlanStorageService _storage;

  List<HealthPlan> _healthPlans = [];
  bool _isLoading = true;

  /// Unmodifiable view of all health plans.
  UnmodifiableListView<HealthPlan> get healthPlans =>
      UnmodifiableListView(_healthPlans);

  /// Returns true while loading from storage.
  bool get isLoading => _isLoading;

  /// Initializes the provider by loading all health plans from storage.
  Future<void> initialize() async {
    _healthPlans = await _storage.loadHealthPlans();
    _sortHealthPlans();
    _isLoading = false;
    notifyListeners();
  }

  /// Saves a health plan (insert or update).
  /// If a plan with the same ID exists, it will be replaced.
  Future<void> saveHealthPlan(HealthPlan plan) async {
    final existingIndex =
        _healthPlans.indexWhere((item) => item.id == plan.id);

    if (existingIndex == -1) {
      _healthPlans = [..._healthPlans, plan];
    } else {
      _healthPlans = [
        for (var index = 0; index < _healthPlans.length; index++)
          if (index == existingIndex) plan else _healthPlans[index],
      ];
    }

    _sortHealthPlans();
    await _storage.saveHealthPlan(plan);
    notifyListeners();
  }

  /// Removes a health plan by ID.
  Future<void> removeHealthPlan(String id) async {
    _healthPlans = _healthPlans.where((plan) => plan.id != id).toList();
    await _storage.deleteHealthPlan(id);
    notifyListeners();
  }

  /// Searches health plans by name, provider, or card number.
  List<HealthPlan> search(String query) {
    if (query.isEmpty) return _healthPlans.toList();

    final normalizedQuery = query.trim().toLowerCase();
    return _healthPlans.where((plan) {
      return plan.name.toLowerCase().contains(normalizedQuery) ||
          plan.provider.toLowerCase().contains(normalizedQuery) ||
          (plan.cardNumber?.contains(query) ?? false);
    }).toList();
  }

  /// Gets a health plan by ID.
  HealthPlan? getById(String id) {
    try {
      return _healthPlans.firstWhere((plan) => plan.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Returns health plans that cover a specific specialty.
  List<HealthPlan> getBySpecialty(String specialty) {
    return _healthPlans
        .where((plan) => plan.specialties.contains(specialty))
        .toList();
  }

  void _sortHealthPlans() {
    _healthPlans.sort((first, second) =>
        first.name.toLowerCase().compareTo(second.name.toLowerCase()));
  }
}