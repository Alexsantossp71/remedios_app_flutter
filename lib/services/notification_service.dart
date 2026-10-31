import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'dose_notification_planner.dart';

/// Schedules system alarms for upcoming doses on mobile (APK).
///
/// Web deliberately stays out: the browser build keeps the in-app reminder
/// (Today screen, including overdue doses on arrival), and this service
/// becomes a no-op behind [kIsWeb] so the same code path ships to both
/// targets. Best-effort by contract: any plugin failure is logged and
/// swallowed so the core treatment flows never depend on notifications.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'dose_reminders';
  static const String _channelName = 'Lembretes de remédio';
  static const String _channelDescription =
      'Alertas no horário de tomar cada dose';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// True after a successful [init] on a mobile target. Providers use it to
  /// skip planning work that would be thrown away on web.
  bool get isReady => _ready;

  /// Idempotent: safe to call from `main()` regardless of platform.
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      tz_data.initializeTimeZones();

      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(initializationSettings);

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+ gates notifications behind a runtime permission; on
      // older versions this call is a no-op.
      await android?.requestNotificationsPermission();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
      _ready = true;
    } on PlatformException catch (error) {
      debugPrint('[NotificationService] init falhou: $error');
    }
  }

  /// Replaces the whole alarm set: cancel everything persisted, schedule the
  /// [doses] the planner projected. Going through the same replace on every
  /// sync (app start, treatment edit, dose status change) means no stale
  /// alarm survives an edit, an archive or a dose taken early.
  Future<void> sync(List<PlannedDose> doses) async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.cancelAll();
      for (final dose in doses) {
        // Alarm scheduling is instant-based: representing the local
        // wall-clock dose time in UTC keeps the exact same moment, so the
        // IANA timezone database is not needed (see ADR 0005). If the device
        // changes timezone afterwards, the next sync re-aligns everything.
        final when = tz.TZDateTime.from(dose.scheduledAt, tz.UTC);
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
          ),
          iOS: DarwinNotificationDetails(),
        );
        try {
          await _plugin.zonedSchedule(
            dose.notificationId,
            'Hora do remédio',
            '${dose.treatmentName} — ${dose.dosage}',
            when,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: dose.treatmentId,
          );
        } on PlatformException {
          // Exact alarms need the user to grant SCHEDULE_EXACT_ALARM on
          // Android 12+. Degrade to inexact instead of losing the reminder
          // entirely.
          await _plugin.zonedSchedule(
            dose.notificationId,
            'Hora do remédio',
            '${dose.treatmentName} — ${dose.dosage}',
            when,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: dose.treatmentId,
          );
        }
      }
    } on PlatformException catch (error) {
      debugPrint('[NotificationService] sync falhou: $error');
    }
  }
}
