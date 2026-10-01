# Never delete treatments to preserve medical history

Prescriptions change. A doctor may stop a medicine, or a user may finish their 10-day antibiotic. Previously, removing a Reminder destroyed the history of that prescription.

**Decision**: Medical treatments are never permanently hard-deleted. Instead, they are deactivated (`isArchived = true`, or `endDate` populated). Data is preserved.

**Consequences**: The UI should filter out archived/past treatments from the "Active" list, but remain searchable under a "History" view. Reports will be able to query past doses.