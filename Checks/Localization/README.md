# Localization checks

```sh
swiftc Checks/Localization/main.swift Sources/NotchIsland/Localization.swift Sources/NotchIsland/AboutProjectContent.swift -o /private/tmp/notch-language-checks
/private/tmp/notch-language-checks
```

Checks both languages, unknown-language fallback, dates locale and all About sections.
Restores the previous language preference. App UI switching is checked separately.
