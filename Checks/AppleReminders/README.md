# Apple Reminders checks

Run from repository root:

```sh
swiftc Sources/NotchIsland/Localization.swift Checks/AppleReminders/main.swift Sources/NotchIsland/AppleReminders.swift Sources/NotchIsland/Reminders.swift Sources/NotchIsland/ReminderView.swift Sources/NotchIsland/ReminderDatePicker.swift -o /private/tmp/apple-reminder-checks
/private/tmp/apple-reminder-checks
```

26 deterministic checks use a fake EventKit repository and temporary migration files.
They verify backup/source preservation, journal deduplication even after deletion,
crash recovery via import markers, failed-save notification preservation, marker
cleanup recovery, six-hour visibility without deletion, undated tasks, edit failure
retention, preserving date/alarms on title edits, completion, reopening, deletion,
and clearing displayed data after permission revocation.

Live macOS checks on 26 October 2026: full-access permission granted, iCloud list
created, legacy record imported twice without duplicates, test record created in
island visible in Apple Reminders, completed in Apple visible in island, reopened
in island visible in Apple, edited due time visible in Apple, test record deleted,
selected list restored after relaunch. User record preserved. Physical iPhone sync,
Apple notification delivery, offline operation, recurrence and macOS 13 remain untested.
