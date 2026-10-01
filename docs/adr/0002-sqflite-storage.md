# Storage migrates from SharedPreferences to SQLite (sqflite)

Medical data — treatments, doses, doctors, consultations — was persisted as a single JSON blob in SharedPreferences. That approach had no querying, no transactional safety, and risked data loss on concurrent writes as the data model grew.

**Decision**: Use SQLite via the `sqflite` plugin as the single local store for all medical data. Add `sqflite_common` for cross-platform DB access. SharedPreferences stays only for non-medical app settings (e.g. UI preferences), never for medical records.

**Consequences**: Requires platform permission entries for the database file path on Android/iOS. Existing SharedPreferences JSON must be migrated once to SQLite on first run. All storage services (`TherapyStorageService`, `DoctorStorageService`, `ConsultationStorageService`) get rewritten against a schema rather than a string blob.