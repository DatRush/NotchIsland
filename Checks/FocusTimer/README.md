# Focus timer

Run on macOS:

```sh
swiftc Sources/NotchIsland/Localization.swift Checks/FocusTimer/main.swift Sources/NotchIsland/FocusTimer.swift -o /private/tmp/notch-focus-checks
/private/tmp/notch-focus-checks
```

60 deterministic checks use an injected clock and an isolated, automatically removed
UserDefaults suite. They cover duration limits (1–86399 seconds), rounded display,
active-session replacement protection, fractional pause/resume, elapsed sleep time,
natural/manual completion, pause at the deadline, reset, hour/minute/second selection,
format transitions, progress, six unique recent durations, promotion on reuse,
persistence, malformed data, and camera geometry including scaled displays, dynamically sized left/right wings,
subsecond progress, paused progress, and the near-completion arc.

Production uses mach_continuous_time (includes sleep, ignores wall-clock changes).
The scheduler runs only while running. Current session state is in-memory; quitting
resets it. Recent durations persist using focusRecentDurations. Completion is a
persistent white visual indicator, without sound or system notifications.

Live checks on the current Mac: keyboard minute/second entry, all three arrow controls,
zero-duration rejection, 45-second natural completion, hour-long timer display and
pause, compact indicator, completion/reset, history selection and restoration after
relaunch. Actual sleep/wake and other display geometries remain unverified. User
visual acceptance remains separate from these checks.

Compact dial refinement: live 45-second run confirmed time on the left, dial on
the right, a nearly full arc at 0:40 and a short arc at 0:08. Reduce Motion and
other displays remain separate live checks.
