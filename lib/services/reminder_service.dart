import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reminder.dart';

class ReminderService {
  static const _key = 'reminders';

  static Future<void> initialize() async {
    // No special init needed for shared_preferences.
    await SharedPreferences.getInstance();
  }

  static Future<List<Reminder>> getAllReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString == null) return [];
    final List<dynamic> decoded = json.decode(jsonString) as List<dynamic>;
    return decoded.map((e) => Reminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> _saveAll(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(reminders.map((r) => r.toJson()).toList());
    await prefs.setString(_key, jsonString);
  }

  static Future<void> addReminder(Reminder reminder) async {
    final current = await getAllReminders();
    current.add(reminder);
    await _saveAll(current);
  }

  static Future<void> updateReminder(Reminder reminder) async {
    final current = await getAllReminders();
    final index = current.indexWhere((r) => r.id == reminder.id);
    if (index != -1) {
      current[index] = reminder;
      await _saveAll(current);
    }
  }
}
