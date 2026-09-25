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

## Project Structure

```
lib/
├── main.dart              - App entry point with HomeScreen UI
├── data/
│   └── medicine_data.dart - Static medicine data for dropdown
├── models/
│   ├── medicine.dart      - Medicine model (name, dosage, presentation)
│   └── reminder.dart      - Reminder model (medicine details + times + taken status)
└── services/
    └── reminder_service.dart - Handles persistence using shared_preferences
```

### Key Components

1. **Main.dart**: Contains the UI with:
   - TableCalendar for date selection
   - ListView for displaying reminders for selected day
   - FloatingActionButton to add new reminders
   - AddReminderDialog for creating/editing reminders

2. **Models**:
   - Medicine: Represents a medicine type with name, dosage, presentation
   - Reminder: Represents a scheduled medicine intake with times and completion status

3. **Services**:
   - ReminderService: Handles loading/saving reminders to shared_preferences using JSON serialization

4. **Data**:
   - MedicineData: Hardcoded list of common medicines for the dropdown selection

## State Management Approach

This app uses Flutter's built-in State management:
- StatefulWidget for HomeScreen (_HomeScreenState)
- setState() calls to refresh UI when data changes
- ReminderService as a singleton for data persistence

## Data Flow

1. App starts → ReminderService.initialize() loads reminders from shared_preferences
2. HomeScreen displays reminders for selected date
3. User adds reminder via dialog → ReminderService.addReminder() saves to shared_preferences
4. User toggles reminder taken → ReminderService.updateReminder() updates shared_preferences
5. On date change → _loadReminders() refreshes the list

## Testing

- Tests are located in the `test/` directory
- Currently contains widget_test.dart (empty)
- To add tests: Create new test files in test/ following Flutter testing conventions
- Use flutter_test package for widget and unit tests

## Dependencies

Key packages in pubspec.yaml:
- flutter/material.dart - UI framework
- shared_preferences: ^2.2.2 - Local storage for reminders
- http: ^1.2.1 - For potential API calls (not currently used)
- table_calendar: ^3.0.9 - Calendar widget
- intl: ^0.18.0 - Internationalization (date formatting)

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
   - Use ReminderService for all shared_preferences operations
   - Convert objects to/from JSON for storage
   - Handle null values and type conversions carefully

## Troubleshooting

- If UI doesn't update: Check that setState() is being called
- If data doesn't persist: Verify ReminderService methods are called correctly
- If build fails: Run flutter pub get to ensure dependencies are installed
- For platform-specific issues: Check android/, ios/, web/, windows/, macos/, linux/ directories