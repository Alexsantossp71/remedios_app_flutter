# Treatment replaces Reminder model for prescriptions and doses

A Reminder was a single medicine intake concept that conflated two concerns: the *prescription* (which medicine, for how long, how often) and the *intake tracking* (did I take it at 8am today?). This caused confusion and made it impossible to:

- Track a single prescription across multiple days
- Show a history of past prescriptions
- Compare actual doses taken vs prescribed

**Decision**: Split into `Treatment` (the prescription) and `Dose` (each intake event). A Treatment belongs to a Medicine; Doses belong to a Treatment.

**Consequences**: The UI needs refactoring to navigate between treatments and their doses. The database schema needs migration. Historical reminders can be converted to treatments with a single dose.