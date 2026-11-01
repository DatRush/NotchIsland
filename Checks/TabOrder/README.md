# Tab order checks

Run from the project root:

```sh
swiftc Checks/TabOrder/main.swift Sources/NotchIsland/TabOrder.swift -o /private/tmp/notch-tab-checks
/private/tmp/notch-tab-checks
```

Checks order normalization, both movement directions, invalid inputs and UserDefaults round-trip. Native drag gestures require a separate UI check.
