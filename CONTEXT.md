# Remédio na Hora

A medicine reminder app that tracks a user's whole medical life: medicines, doctors, consultations, and the actual doses taken over time.

## Language

A **Medicine** is a named product (e.g. Amoxicilina 500mg, capsula) with an active ingredient, dosage, presentation, aliases, and EANs. It is *not* a prescription — it is the catalog entry the user searches when adding a treatment.

A **Treatment** (formerly "Reminder") is a prescription: a single medicine the user was told to take, with a dosage, a presentation, a start date, an end date, and an active/inactive flag. A treatment is never deleted — it is deactivated, so the medical history stays intact.

A **Dose** (formerly "Reminder.taken") is one intake event: a specific time on a specific day for a specific treatment. Doses are the unit of "did I take it today" tracking.

A **Doctor** is a physician the user has seen, with CRM, specialty, clinic address, health plans, and notes.

A **Consultation** is a visit to a doctor, with a date, title, notes, status (scheduled / completed / cancelled), and an optional return date.

**Prescription** and **treatment** are synonyms; use **treatment**. **Dose** and **intake** are synonyms; use **dose**. Do not use "reminder" for the new model — it was the old name for what is now a treatment.

## Rules

- A treatment is identified by a stable UUID and is never deleted. Deactivation is a status change.
- A dose is identified by a stable UUID and belongs to exactly one treatment.
- Times are stored in UTC. The app converts to the device's local timezone for display and for "is it time yet" checks.
- Fixed-interval drugs (antibiotics, chronic meds) compute their next dose from the interval. Local-time drugs (vitamins, as-needed) fire at a fixed local hour.
- All medical data lives in a local SQLite database (sqflite), migrated away from SharedPreferences.

## Out of scope

- Sharing data between devices.
- Cloud backups.
- Pharmacy inventory or price lookups.
- Dose reminders firing outside the app (notifications are a future step).