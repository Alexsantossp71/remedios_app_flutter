# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter application called "Remédio na Hora" (Medicine on Time) — a personal health organizer that allows users to:

- Add medicine reminders with specific times, frequency and weekdays
- Mark medicines as taken/skipped and track adherence
- View reminders by calendar date and historical adherence
- Persist medical data in a local encrypted SQLite database
- Track doctors, consultations, exams and lab results
- Read prescriptions and health-plan cards via OCR (Tesseract.js)
- Generate AI-assisted summaries of lab results (opt-in, with LGPD consent)
- Export/import encrypted backups (AES-256-GCM with user password)
- Run on Web, Android, iOS, macOS, Windows and Linux

## Development Commands

### Flutter Commands
- `flutter pub get` — Install dependencies (use `--enforce-lockfile` in CI)
- `flutter run -d <device>` — Run on connected device/emulator/browser
- `flutter build web --release` — Build the Web release (deployed to Vercel)
- `flutter build apk` — Build Android APK
- `flutter build ios` — Build iOS app
- `flutter test` — Run all unit/widget tests
- `flutter test test/widget_test.dart` — Run a specific test file
- `flutter analyze --no-fatal-infos` — Run Dart analyzer (warnings/errors blocking; infos tolerated)
- `dart format --output=none lib test` — Report formatting drift without modifying files
- `flutter clean` — Clean build artifacts

### Web SQLite preparation (CI-only)
The CI regenerates the SQLite3MultipleCiphers WASM and worker before testing:
```bash
dart run sqflite_common_ffi_web:setup --force
curl -fsSLo web/sqlite3.wasm <sqlite3mc.wasm release URL>
echo "<sha256>  web/sqlite3.wasm" | sha256sum -c -
dart compile js -O2 -o web/sqlite3_mc_sw.js web/sqlite3mc_shared_worker.dart
```

### Serverless API (api/, Vercel)
- `api/ping.ts` — runtime probe
- `api/read-card.ts` — health-plan card OCR
- `api/read-receita.ts` — prescription OCR
- `api/places.ts` — address autocomplete (OpenStreetMap Nominatim proxy)
See `api/openapi.yaml` for the full HTTP contract.

## Agent skills

### Issue tracker
Issues and specs live as GitHub issues. See `docs/agents/issue-tracker.md`.

### Domain docs
Single-context layout (`CONTEXT.md` + `docs/adr/` at the repo root). See `docs/agents/domain.md`.

## Project Structure (v3.0.0+0)

```
lib/
├── main.dart                          App entry: bootstrapApp() + MultiProvider
├── core/
│   ├── theme/app_theme.dart           Light + dark themes (V3 Clínico calmo)
│   ├── design/                        Design system: app_shell, brand_mark,
│                                      brand_colors, dashboard_hero, quick_action,
│                                      record_card, stat_card, app_tokens
│   └── lab_values.dart                Reference intervals for lab results
├── data/
│   ├── medicine_data.dart             Static medicine catalog (assets/data/)
│   └── medical_specialties.dart       Specialty list for doctor form
├── models/                            13 pure domain classes (no Flutter dep):
│   consultation, doctor, doctor_draft, dose_event, emergency_contact,
│   exam, health_plan, lab_result, medicine, prescription_record,
│   treatment, treatment_draft, user_profile
├── providers/                         7 ChangeNotifiers (state layer):
│   consultation, doctor, exam, health_plan, lab_result, therapy, user_profile
├── screens/                           14 screens, including:
│   ├── main_shell.dart                Bottom-nav shell (replaces old HomeScreen)
│   ├── today_screen.dart              Today's doses
│   ├── treatments_screen.dart         Active + archived treatments
│   ├── progress_screen.dart           Adherence dashboard
│   ├── doctors_screen.dart
│   ├── consultations_screen.dart
│   ├── exams_screen.dart
│   ├── lab_results_screen.dart
│   ├── health_plans_screen.dart
│   ├── profile_screen.dart
│   ├── prescription_review_screen.dart
│   ├── health_plan_review_screen.dart
│   ├── barcode_scan_screen.dart
│   └── create_flows.dart
├── services/                          48 services, organized by concern:
│   ├── database_service.dart          Singleton SQLite, schema v11, migrations
│   ├── database_factory_web.dart      sqflite_common_ffi_web factory
│   ├── database_factory_io.dart       sqflite_common_ffi factory (native)
│   ├── database_encryption/           SQLite3MC open + key pragmas + migration:
│   │   ├── database_encryption_service.dart
│   │   ├── database_encryption_service_io.dart
│   │   ├── database_encryption_service_web.dart
│   │   ├── encrypted_database_opener.dart
│   │   ├── encrypted_database_opener_stub.dart
│   │   ├── database_migration_io.dart
│   │   ├── database_migration_web.dart
│   │   ├── database_preservation.dart
│   │   └── encryption_pragmas.dart
│   ├── database_key/                  DEK storage (Android Keystore / WebCrypto):
│   │   ├── database_key_service.dart
│   │   ├── database_key_store.dart
│   │   ├── android_database_key_store.dart
│   │   ├── web_database_key_store.dart
│   │   ├── web_key_storage.dart
│   │   ├── web_local_storage_binding.dart
│   │   ├── web_local_storage_stub.dart
│   │   ├── in_memory_database_key_store.dart
│   │   └── recovery_envelope.dart
│   ├── therapy_storage_service.dart   Treatments + doses + prescriptions
│   ├── doctor_storage_service.dart
│   ├── consultation_storage_service.dart
│   ├── exam_storage_service.dart
│   ├── lab_result_storage_service.dart
│   ├── health_plan_storage_service.dart
│   ├── backup_service.dart             Export/import with AES-256-GCM
│   ├── backup_crypto_service.dart      Crypto envelope for backups
│   ├── backup_file.dart + _io + _web   Platform-aware file I/O
│   ├── notification_service.dart       flutter_local_notifications (mobile)
│   ├── dose_notification_planner.dart
│   ├── dose_schedule_presets.dart
│   ├── web_reminder_service.dart       In-browser dose reminders
│   ├── web_reminder_platform_web.dart + _stub.dart
│   ├── ai_service.dart                 AI summaries (lab, exam, doctor extract)
│   ├── ai_proxy_client.dart
│   ├── prescription_reader_service.dart
│   ├── card_reader_service.dart
│   ├── crm_lookup_service.dart
│   ├── cep_lookup_service.dart
│   ├── places_search_service.dart
│   ├── doctor_matching.dart
│   └── emergency_card_share_service.dart
└── widgets/                            26 reusable components, including:
    database_unlock_gate, treatment_form_dialog, doctor_form_dialog,
    consultation_form_dialog, exam_form_dialog, health_plan_form_dialog,
    lab_result_review_sheet, ai_*_sheet (4), stepped_form_sheet,
    create_choice_sheet, add_health_plan_sheet, reading_dialog,
    privacy_notice, emergency_card, empty_state, empty_illustration,
    skeleton, info_chip, section_header, app_snack_bar, br_input_formatters,
    media_source_sheet, doctor_inline_creator, ai_sheet_shell, ai_interactions_sheet

android/app/src/main/kotlin/com/example/remedios_app_flutter/
├── MainActivity.kt                    Method-channel host
└── security/AndroidDatabaseKeyStore.kt  DEK wrapped by Android Keystore (AES-GCM)

ios/Runner/                             iOS host (encryption: see P1-5 roadmap)
macos/Runner/                           macOS host
web/                                    SQLite3MC WASM + shared worker
```

## Key Components

1. **main.dart**: Entry point. Web boots through `DatabaseUnlockGate` (explicit unlock + recovery envelope); native bootstraps directly. `bootstrapApp()` instantiates 7 providers, awaits sequential `initialize()`, registers them via `MultiProvider` + `ChangeNotifierProvider.value`, and runs `RemediosApp` (MaterialApp with light + dark themes, pt-BR primary locale).

2. **Models** (13 classes): Pure Dart, no Flutter dependency. Use `copyWith` for immutable updates. Convert to/from `Map<String, dynamic>` for SQLite persistence.

3. **Providers** (7 ChangeNotifiers): Mediate between services and widgets. Expose `UnmodifiableListView` to prevent external mutation. TherapyProvider is the largest (treatments + doses + prescriptions + notification sync).

4. **Services** (48 files): Persistence, encryption, AI, OCR, notifications, backups. Each domain has its own `*StorageService` (typed). `DatabaseService` is the singleton SQLite gateway with schema v11 + incremental migrations.

5. **Screens** (14): Routed through `MainShell` (bottom-nav with Today/Treatments/Progress/More). Each screen owns its forms via dialogs in `widgets/`.

6. **Widgets** (26): Reusable dialogs, sheets, cards, empty states, design-system primitives in `core/design/`.

7. **Database encryption** (Android + Web, delivered in PR #64): SQLite3MultipleCiphers with ChaCha20. DEK stored in Android Keystore (native) or WebCrypto (web, with PBKDF2-HMAC-SHA256 + AES-256-GCM recovery envelope). iOS/macOS/Windows/Linux remain on legacy plaintext (see ADR 0003 and roadmap).

## Data Flow

1. App starts → `DatabaseService.instance.database` resolves the key, runs legacy → encrypted migration if needed, opens with PRAGMAs, validates key, runs schema v11 migrations → returns `Database`.
2. Each provider's `initialize()` loads its domain records via the corresponding `*StorageService` (which queries SQLite directly).
3. UI subscribes via `context.watch<T>()` / reads via `context.read<T>()`.
4. User action → provider method → mutates in-memory list + persists via storage service + `notifyListeners()`.
5. Therapy changes → `_syncDoseNotifications()` replans local notifications (mobile) or web reminders (browser).

## Testing

- Unit/widget tests in `test/` (64 files): models, services, providers, widgets.
- Integration tests in `integration_test/` (4 flows: consultation, healthplan, medicine, app).
- End-to-end tests in `e2e/` (Playwright): setup, medicines, consultations, health_plans, doctors, diagnose.
- Database encryption tests in `test/services/database_encryption/` (key service, migration, recovery envelope, web key store).
- Test infra: `DatabaseService.initInMemoryDatabase()` + `@visibleForTesting` overrides (`encryptionServiceOverride`, `setDatabaseForTesting`, `applyUpgradesForTesting`, `createSchemaForTesting`).
- CI: `.github/workflows/flutter-ci.yml` runs pub get (lockfile-enforced), SQLite3MC WASM regen with sha256 check, format drift report, analyze (--no-fatal-infos), test, build web.

## Dependencies

Key packages in `pubspec.yaml` (Dart >=3.12):
- flutter, cupertino_icons, flutter_localizations — UI
- sqflite, sqflite_common, sqflite_common_ffi, sqflite_common_ffi_web, sqlite3 — SQLite with SQLite3MC build hook
- path, path_provider — File paths
- shared_preferences — Non-medical app settings only
- provider — State management (ChangeNotifier)
- uuid — IDs
- intl, flutter_localizations, timezone — i18n and timezones
- table_calendar — Calendar widget
- http — API client (places, CRM, CEP, AI proxy)
- image_picker, mobile_scanner, file_picker — Media input
- share_plus — Emergency card sharing
- cryptography — AES-256-GCM backup encryption
- synchronized — Concurrency
- flutter_local_notifications — Local alarms
- web — Browser interop (WebReminderService)

Dev: flutter_test, integration_test, flutter_driver, test, flutter_lints (^5.0.0).

## Architectural Decision Records (ADRs)

Located in `docs/adr/`:
- `0001-treatment-data-model.md` — Treatment model
- `0002-sqflite-storage.md` — SharedPreferences → SQLite migration
- `0003-local-database-encryption.md` — SQLite3MC + ChaCha20 (Android/Web delivered)
- `0004-database-key-management-and-recovery.md` — DEK/KEK separation + recovery envelope
- `0005-local-notifications-mobile.md` — Mobile local notifications
- `0006-react-design-system.md` — V3 design system
- `0007-preserve-treatment-history.md` — Treatments never hard-deleted (renumerado de 0003)
- `0008-utc-scheduling.md` — UTC storage for schedule safety (renumerado de 0004)

## Common Development Patterns

1. **Adding a new domain entity**:
   - Add model in `lib/models/`
   - Add `*StorageService` in `lib/services/`
   - Add `*Provider` (ChangeNotifier) in `lib/providers/`
   - Register in `main.dart`'s `bootstrapApp()` MultiProvider list
   - Add `*_storage_service_test.dart` and `*_provider_test.dart`
   - Add screens/widgets as needed
   - Update `DatabaseService._onCreate` + `_onUpgrade` if a new table is needed (bump `_databaseVersion`)

2. **UI updates**: Use `context.watch` for rebuild-on-change, `context.read` for one-shot actions. Extract reusable components to `lib/widgets/`. Forms typically use `SteppedFormSheet` or `*FormDialog` patterns.

3. **Persistence**: Use the domain-specific `*StorageService` (typed). Never use the legacy `lib/services/storage_service.dart` — it was removed in P1-1 (19/11/2026) as dead code with a saveTreatments bug. All persistence goes through `DatabaseService.instance.database`.

4. **Encryption**: New platforms must implement the contract in ADR 0003 + 0004 — generate random DEK, wrap in OS key store (Keystore/Keychain/WebCrypto), never log/commit/embed, fail safe (never create empty DB over existing path), test recovery envelope.

## Troubleshooting

- **UI doesn't update**: Verify `notifyListeners()` is called after state mutation.
- **Data doesn't persist**: Check that the provider delegates to the `*StorageService`, not to in-memory state alone.
- **Database won't open (Android/Web)**: Check `DatabaseService.lastOpenError`; key recovery flow is via `DatabaseUnlockGate` (Web) or `KeyRecoveryRequiredException` (Android).
- **Build fails on Web**: Regenerate `web/sqlite3.wasm` and `web/sqlite3_mc_sw.js` per CI steps; verify sha256.
- **Format/analyze drift**: `dart format lib test` to fix; `flutter analyze --no-fatal-infos` to verify.
- **Platform-specific issues**: Check `android/`, `ios/`, `web/`, `macos/`, `windows/`, `linux/` directories.
