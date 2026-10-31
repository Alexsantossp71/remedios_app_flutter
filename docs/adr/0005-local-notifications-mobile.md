# Mobile gets exact system alarms for dose reminders; web stays in-app

**Date**: 2026-10-31

## Context

The app's core promise is alerting at dose time. On web, the Today screen
already covers it: opening the site shows the day's doses, including the
overdue ones. On an installed APK the process is usually dead, so nothing
would ever fire — `flutter_local_notifications` was declared in pubspec but
never wired up.

Two facts from the existing design constrain the scheduler:

1. `DoseEvent` rows only exist for the current day (generated on open by
   `TherapyProvider.ensureDoseEventsFor`). Scheduling from stored events
   would go silent whenever the user skips a day.
2. ADR 0004: a daily medicine is a local wall-clock intent ("8 AM local"),
   not a fixed absolute instant.

## Decision

1. Notifications are projected straight from the treatment rules by
   `DoseNotificationPlanner` — the same `Treatment.isScheduledOn` rule used
   for event generation — over a 7-day horizon capped at 100 alarms.
2. `NotificationService` replaces the whole alarm set on every sync
   (`cancelAll` + schedule). Sync runs on app start, any treatment
   add/edit/archive and any dose status change. The replace-everything
   strategy is idempotent and needs no incremental bookkeeping: no stale
   alarm survives an edit, an archive or a dose taken early.
3. Alarm instants are the local wall-clock dose times represented in UTC.
   Alarm scheduling is instant-based, so no IANA timezone database is
   required. If the device crosses a timezone afterwards, the next sync
   (any app open) re-aligns everything with the new local wall clock.
4. Android: exact alarms (`SCHEDULE_EXACT_ALARM`, `exactAllowWhileIdle`)
   with graceful fallback to inexact when the user denies the permission;
   `POST_NOTIFICATIONS` runtime permission (Android 13+); the plugin's boot
   receiver re-schedules after reboot/app update. Web: the service is a
   no-op behind `kIsWeb`.

## Consequences

- The APK asks for notification and exact-alarm permissions on first run;
  without the exact-alarm grant the reminder still fires, just within a
  system-defined window.
- Core library desugaring becomes mandatory in the Android build (the
  plugin uses java.time), configured in `android/app/build.gradle.kts`.
- Notifications are best-effort: every failure is logged and swallowed so
  the core treatment flows never depend on them.
