# Schedule storage uses absolute UTC for safety

Devices change timezones and daylight saving time shifts. If a fixed-interval dose (every 8 hours) is stored in local time, daylight saving shifts will miscalculate the next absolute dose time, posing a health risk (e.g. antibiotics).

**Decision**: 
1. All timestamp events (`scheduledAt` for `DoseEvent`, `startDate` for `Treatment`) are stored strictly in UTC.
2. The UI layer computes local time at display-time.
3. For daily local-time medicines (like vitamins "always at 8 AM local"), the system stores the intent (schedule rule: 8 AM local) rather than a rigid absolute time.

**Consequences**: Services converting JSON from SQLite MUST parse as UTC (`DateTime.parse(str).toUtc()`). Generation of future `DoseEvent` records must respect the treatment frequency rule depending on its domain type.