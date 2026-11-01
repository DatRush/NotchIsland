# Timer notice / screenshot coordination

```sh
swiftc Checks/TimerNotice/main.swift Sources/NotchIsland/TimerNoticeGate.swift -o /private/tmp/timer-notice-checks
/private/tmp/timer-notice-checks
```

26 deterministic checks cover timer expiry while capturing: successful screenshot,
GPT attachment, cancellation and failure. They exercise the production deferral
state, including exactly-once presentation. They do not drive the system screenshot
picker or assert WindowServer visibility; live UI race verification remains separate.
