# Standard editing menu

On macOS:

```sh
swiftc Sources/NotchIsland/Localization.swift Checks/EditingMenu/main.swift Sources/NotchIsland/EditingMenu.swift -o /private/tmp/notch-editing-menu
/private/tmp/notch-editing-menu
```

Verifies editing selectors, shortcuts, nil targets for responder-chain routing and actual Command-V menu dispatch; unrelated modifiers do not dispatch paste. No clipboard or account data is accessed. Live WebKit input and paste are checked separately in the installed app.
