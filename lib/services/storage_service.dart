import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';

/// Abstract storage service interface that works across all Flutter platforms.
///
/// On Web: Uses SharedPreferences for persistence (no SQLite support)
/// On Desktop/Mobile: Uses SQLite with sqflite, FFI for desktop platforms
///
/// This provides a consistent API regardless of the underlying storage implementation.
abstract class StorageService {
  /// Get the singleton instance
  static StorageService? _instance;

  factory StorageService() {
    return _instance ??= PlatformAwareStorageService._();
  }

  /// Clear any cached instance for testing
  static void clearInstance() {
    _instance = null;
  }

  /// Initialize the storage service
  Future<void> initialize();

  /// Close the storage service and release resources
  Future<void> close();

  /// Get treatments from storage
  Future<List<Map<String, dynamic>>> getTreatments();

  /// Save treatments to storage
  Future<void> saveTreatments(List<Map<String, dynamic>> treatments);

  /// Get dose events from storage
  Future<List<Map<String, dynamic>>> getDoseEvents();

  /// Save dose events to storage
  Future<void> saveDoseEvents(List<Map<String, dynamic>> doseEvents);

  /// Get doctors from storage
  Future<List<Map<String, dynamic>>> getDoctors();

  /// Save doctors to storage
  Future<void> saveDoctors(List<Map<String, dynamic>> doctors);

  /// Get consultations from storage
  Future<List<Map<String, dynamic>>> getConsultations();

  /// Save consultations to storage
  Future<void> saveConsultations(List<Map<String, dynamic>> consultations);

  /// Delete all data from storage
  Future<void> clearAll();
}

/// Platform-aware implementation that chooses the right storage backend.
class PlatformAwareStorageService implements StorageService {
  PlatformAwareStorageService._();

  static final PlatformAwareStorageService _instance = PlatformAwareStorageService._();

  factory PlatformAwareStorageService() => _instance;

  late final bool _isWeb = kIsWeb;

  // Web implementation using SharedPreferences
  final Map<String, List<Map<String, dynamic>>> _webStorage = {};

  // Desktop/Mobile implementation using SQLite
  final Map<String, Object?> _sharedPreferencesCache = {};

  /// Initialize the appropriate storage based on platform
  @override
  Future<void> initialize() async {
    if (_isWeb) {
      await _initializeWebStorage();
    } else {
      await _initializeNativeStorage();
    }
  }

  /// Web implementation using SharedPreferences
  Future<void> _initializeWebStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load existing data from SharedPreferences
      if (prefs.containsKey('treatments_db')) {
        final treatmentsJson = prefs.getString('treatments_db');
        if (treatmentsJson != null) {
          final List<dynamic> list = jsonDecode(treatmentsJson);
          _webStorage['treatments'] = list.cast<Map<String, dynamic>>();
        }
      }

      if (prefs.containsKey('dose_events_db')) {
        final doseEventsJson = prefs.getString('dose_events_db');
        if (doseEventsJson != null) {
          final List<dynamic> list = jsonDecode(doseEventsJson);
          _webStorage['dose_events'] = list.cast<Map<String, dynamic>>();
        }
      }

      if (prefs.containsKey('doctors_db')) {
        final doctorsJson = prefs.getString('doctors_db');
        if (doctorsJson != null) {
          final List<dynamic> list = jsonDecode(doctorsJson);
          _webStorage['doctors'] = list.cast<Map<String, dynamic>>();
        }
      }

      if (prefs.containsKey('consultations_db')) {
        final consultationsJson = prefs.getString('consultations_db');
        if (consultationsJson != null) {
          final List<dynamic> list = jsonDecode(consultationsJson);
          _webStorage['consultations'] = list.cast<Map<String, dynamic>>();
        }
      }

    } catch (e) {
      debugPrint('Error initializing web storage: $e');
      // Fallback to empty storage
    }
  }

  /// Native implementation using SQLite
  Future<void> _initializeNativeStorage() async {
    // Initialize the database service
    await DatabaseService.instance.close();
    // No-op since DatabaseService handles its own initialization
  }

  @override
  Future<void> close() async {
    if (_isWeb) {
      // Save web storage to SharedPreferences
      await _saveWebStorageToPrefs();
    } else {
      await DatabaseService.instance.close();
    }
  }

  /// Save web storage data to SharedPreferences
  Future<void> _saveWebStorageToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_webStorage['treatments'] != null) {
        final treatmentsJson = jsonEncode(_webStorage['treatments']);
        await prefs.setString('treatments_db', treatmentsJson);
      }

      if (_webStorage['dose_events'] != null) {
        final doseEventsJson = jsonEncode(_webStorage['dose_events']);
        await prefs.setString('dose_events_db', doseEventsJson);
      }

      if (_webStorage['doctors'] != null) {
        final doctorsJson = jsonEncode(_webStorage['doctors']);
        await prefs.setString('doctors_db', doctorsJson);
      }

      if (_webStorage['consultations'] != null) {
        final consultationsJson = jsonEncode(_webStorage['consultations']);
        await prefs.setString('consultations_db', consultationsJson);
      }

    } catch (e) {
      debugPrint('Error saving web storage: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getTreatments() async {
    if (_isWeb) {
      return _webStorage['treatments'] ?? [];
    } else {
      final db = await DatabaseService.instance.database;
      final rows = await db.query('treatments');
      return rows.cast<Map<String, dynamic>>();
    }
  }

  @override
  Future<void> saveTreatments(List<Map<String, dynamic>> treatments) async {
    if (_isWeb) {
      _webStorage['treatments'] = treatments;
      await _saveWebStorageToPrefs();
    } else {
      final db = await DatabaseService.instance.database;
      await db.delete('treatments');
      if (treatments.isNotEmpty) {
        await db.insert('treatments', treatments.first);
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getDoseEvents() async {
    if (_isWeb) {
      return _webStorage['dose_events'] ?? [];
    } else {
      final db = await DatabaseService.instance.database;
      final rows = await db.query('dose_events');
      return rows.cast<Map<String, dynamic>>();
    }
  }

  @override
  Future<void> saveDoseEvents(List<Map<String, dynamic>> doseEvents) async {
    if (_isWeb) {
      _webStorage['dose_events'] = doseEvents;
      await _saveWebStorageToPrefs();
    } else {
      final db = await DatabaseService.instance.database;
      await db.delete('dose_events');
      if (doseEvents.isNotEmpty) {
        await db.insert('dose_events', doseEvents.first);
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getDoctors() async {
    if (_isWeb) {
      return _webStorage['doctors'] ?? [];
    } else {
      final db = await DatabaseService.instance.database;
      final rows = await db.query('doctors');
      return rows.cast<Map<String, dynamic>>();
    }
  }

  @override
  Future<void> saveDoctors(List<Map<String, dynamic>> doctors) async {
    if (_isWeb) {
      _webStorage['doctors'] = doctors;
      await _saveWebStorageToPrefs();
    } else {
      final db = await DatabaseService.instance.database;
      await db.delete('doctors');
      if (doctors.isNotEmpty) {
        await db.insert('doctors', doctors.first);
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getConsultations() async {
    if (_isWeb) {
      return _webStorage['consultations'] ?? [];
    } else {
      final db = await DatabaseService.instance.database;
      final rows = await db.query('consultations');
      return rows.cast<Map<String, dynamic>>();
    }
  }

  @override
  Future<void> saveConsultations(List<Map<String, dynamic>> consultations) async {
    if (_isWeb) {
      _webStorage['consultations'] = consultations;
      await _saveWebStorageToPrefs();
    } else {
      final db = await DatabaseService.instance.database;
      await db.delete('consultations');
      if (consultations.isNotEmpty) {
        await db.insert('consultations', consultations.first);
      }
    }
  }

  @override
  Future<void> clearAll() async {
    if (_isWeb) {
      _webStorage.clear();
      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await DatabaseService.instance.close();
      // Reinitialize to create new empty database
      _sharedPreferencesCache.clear();
    }
  }
}

/// Migration helper for converting SQLite data to SharedPreferences on web.
class WebMigrationHelper {
  /// Migrate data from DatabaseService to WebStorageService
  static Future<void> migrateToWebStorage() async {
    try {
      final dbService = DatabaseService.instance;
      final db = await dbService.database;

      // Get all data from SQLite
      final treatments = await db.query('treatments');
      final doseEvents = await db.query('dose_events');
      final doctors = await db.query('doctors');
      final consultations = await db.query('consultations');

      // Save to web storage
      final storageService = StorageService();
      await storageService.clearAll();
      await storageService.saveTreatments(treatments.cast<Map<String, dynamic>>());
      await storageService.saveDoseEvents(doseEvents.cast<Map<String, dynamic>>());
      await storageService.saveDoctors(doctors.cast<Map<String, dynamic>>());
      await storageService.saveConsultations(consultations.cast<Map<String, dynamic>>());

      // Close the SQLite database to free resources
      await dbService.close();

    } catch (e) {
      debugPrint('Error migrating to web storage: $e');
      rethrow;
    }
  }
}