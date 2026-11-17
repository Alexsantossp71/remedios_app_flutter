# Fresh database rollout and legacy-data preservation

## What changes

The app now opens a new SQLite namespace, `remedios_app_fresh_v1.db`, on native
platforms and the corresponding logical database name on Web. The existing
`remedios_app.db` is not deleted, renamed, migrated, or overwritten.

The new database is created with the current schema (v11) and starts empty.
The old SharedPreferences JSON values (including `treatments_db`,
`dose_events_db`, `doctors_db`, and `consultations_db`) are not imported or
deleted. The legacy migration flag `sqlite_migration_completed_v1` is not
changed.

The static medicine catalog at `assets/data/medicine_catalog.json` is not
database data and remains packaged with the app.

## Recovery / rollback

- Native: the prior `remedios_app.db` file remains in the app documents
  directory. To roll back the code-level namespace switch, restore the previous
  database name in `DatabaseService` and reinstall/build the previous app
  version. Do not delete either database until the old data has been reviewed.
- Web: the old logical database name remains in browser storage; the new name
  creates a separate database. Browser storage clearing can still remove both,
  so users must not clear site data if they need the old data.
- Legacy SharedPreferences values are intentionally left untouched.

This is a clean-start isolation strategy, not a data migration, backup export,
or database-encryption implementation. It does not prove that an application
startup failure was caused by stale database contents; CI and platform smoke
tests are still required. Do not claim the active database is encrypted.

## Release verification checklist

1. Confirm a fresh install creates all schema v11 tables in the new database.
2. Confirm the app can create, read, update, and delete a treatment and dose event.
3. Confirm the previous database file / Web logical database still exists.
4. Confirm legacy SharedPreferences values and migration flag are unchanged.
5. Confirm the medicine catalog loads from the bundled JSON asset.
6. Test Android, iOS, Windows, Linux, macOS, and supported browsers before
   production rollout.
