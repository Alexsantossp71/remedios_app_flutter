# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter application called "Remédio na Hora" (Medicine on Time) - a medicine reminder app that allows users to:
- Add medicine reminders with specific times
- Mark medicines as taken
- View reminders by calendar date
- Persist reminders using shared preferences

## Development Commands

### Flutter Commands
- `flutter pub get` - Install dependencies
- `flutter run` - Run the app on connected device/emulator
- `flutter build apk` - Build Android APK
- `flutter build ios` - Build iOS app
- `flutter test` - Run all tests
- `flutter test test/widget_test.dart` - Run specific test file
- `flutter analyze` - Run Dart analyzer
- `flutter format lib/ test/` - Format Dart code

### Common Tasks
- To run on a specific device: `flutter run -d <device-id>`
- To enable web support: `flutter config --enable-web` then `flutter run -d chrome`
- To clean build: `flutter clean`

## Agent skills

### Issue tracker

Issues and specs for this repo live as GitHub issues. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout (`CONTEXT.md` + `docs/adr/` at the repo root). See `docs/agents/domain.md`.

## Project Structure

```
lib/
├── main.dart              - App entry point with HomeScreen UI
├── data/
│   └── medicine_data.dart - Static medicine data for dropdown
├── models/
│   ├── medicine.dart      - Medicine model (name, dosage, presentation)
│   └── treatment.dart      - Treatment model (medicine details + dose times + archived status)
└── services/
    └── therapy_storage_service.dart - Handles persistence using SQLite (sqflite)
```

## Key Components

1. **Main.dart**: Contains the UI with:
   - TableCalendar for date selection
   - ListView for displaying reminders for selected day
   - FloatingActionButton to add new reminders
   - AddReminderDialog for creating/editing reminders

2. **Models**:
   - Medicine: Represents a medicine type with name, dosage, presentation
   - Treatment: Represents a scheduled medicine intake with times and archived status

3. **Services**:
   - TherapyStorageService: Handles persistence using SQLite (sqflite) for treatments and dose events

## Data Flow

1. App starts → TherapyStorageService.loadTreatments() loads treatments from SQLite
2. HomeScreen displays reminders for selected date (derived from treatments)
3. User adds treatment via dialog → TherapyStorageService.saveTreatment() saves to SQLite
4. User marks dose taken → TherapyProvider.setDoseStatus() updates status and stock
5. On date change → TherapyProvider.ensureDoseEventsFor() refreshes dose events

## Testing

- Tests are located in the `test/` directory
- Includes widget_test.dart, sqlite_storage_test.dart, and other tests for models and services
- To add tests: Create new test files in test/ following Flutter testing conventions
- Use flutter_test package for widget and unit tests
- Use flutter_test package for widget and unit tests

## Dependencies

Key packages in pubspec.yaml:
- flutter/material.dart - UI framework
- sqflite: ^2.4.1 - SQLite database
- sqflite_common_ffi: ^2.3.4+4 - SQLite FFI for desktop
- path: ^1.9.0 - Path utilities
- path_provider: ^2.1.5 - Path provider
- http: ^1.2.1 - For potential API calls (not currently used)
- table_calendar: ^3.0.9 - Calendar widget
- intl: ^0.20.2 - Internationalization (date formatting)
- provider: ^6.1.5+1 - State management
- uuid: ^4.5.1 - UUID generation

## Common Development Patterns

1. **Adding New Features**:
   - Create new model classes in lib/models/ if needed
   - Add service methods in lib/services/ for data operations
   - Update UI in lib/main.dart or create new widgets
   - Test with flutter test

2. **UI Updates**:
   - Use StatefulWidget with setState() for simple state
   - Consider extracting complex widgets to separate files
   - Follow Material Design guidelines

3. **Data Persistence**:
   - Use TherapyStorageService for all SQLite operations
   - Convert objects to/from JSON for storage
   - Handle null values and type conversions carefully

## Troubleshooting

- If UI doesn't update: Check that setState() is being called
- If data doesn't persist: Verify TherapyProvider methods are called correctly
- If build fails: Run flutter pub get to ensure dependencies are installed
- For platform-specific issues: Check android/, ios/, web/, windows/, macos/, linux/ directories