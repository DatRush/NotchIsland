# Reminders

Run on macOS:

```sh
swiftc Sources/NotchIsland/Localization.swift Checks/Reminders/main.swift Sources/NotchIsland/Reminders.swift Sources/NotchIsland/ReminderNotifications.swift -o /private/tmp/notch-reminder-checks
/private/tmp/notch-reminder-checks
```

50 checks use an injected clock, in-memory persistence, a fake notification service,
and a disposable temporary directory. No real authorization request or notification
is issued by these checks. The real notification request builder is checked without
creating a notification center.

Coverage: text/date/count validation, denied/delayed authorization, one-shot timeout
completion, atomic file round-trip, malformed files and duplicate IDs, write failure,
scheduling failure and retry, restoration without duplicate or overdue alerts,
revoked permission, owned-orphan cancellation, deletion failure, source text and
safe HTTP(S) links, absolute trigger time with fractional-second rounding, generic
notification body, no sound, and notification-to-record identity.

Storage: Application Support/NotchIsland/reminders.json, version 1, up to 32 active
reminders and 4000 characters each. Corrupt storage is left intact and writes disabled.
A reminder is saved before its notification is scheduled. Deletion commits before
cancelling pending/delivered requests. Notification acceptance is not proof of delivery.
Live checks on October 25: user granted permission; notification accepted and recorded
in Notification Center. macOS suppressed the banner due to display sharing (confirmed
by usernoted/NotificationCenter logs). The user clicked it in Notification Center and
confirmed the correct saved text opened. Relaunch restored the list; an HTTP(S) link
opened in the default browser. Both test reminders were completed and the test tab
closed. The final installed build includes the authorization timeout.

Clipboard import, closed-app delivery, sleep/wake and other Macs remain separate
live checks. User visual acceptance of the reminder UI is still open.


October 26 compact UI regression check: the inline NSDatePicker uses no calendar
overlay. Live clicks, keyboard day/hour/minute changes and the stepper kept the
island open. Changing draft text preserved the selected date. List/editor/detail
fit the standard 405 × 240 size; Esc still collapsed the island. Dedicated copy,
open-link and duplicate delete buttons were removed; links are now clickable text.
The 50 logic checks do not claim to automate these native UI interactions.

History update: 58 checks now cover completion persistence, notification cancellation, restart without rescheduling, six-hour expiry, failed writes and manual history deletion.

61 checks: reopening future/completed reminders restores notifications; overdue records do not re-alert; failed saves preserve completion.
