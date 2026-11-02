# Music checks

Run on macOS:

```sh
swiftc Sources/NotchIsland/Localization.swift Checks/Music/main.swift Sources/NotchIsland/YouTubeMusicFilter.swift Sources/NotchIsland/MusicPlayback.swift Sources/NotchIsland/MusicArtworkCapture.swift Sources/NotchIsland/RemoteArtwork.swift -o /private/tmp/notch-music-checks
/private/tmp/notch-music-checks
```

37 checks cover time parsing, active-source selection, new playback priority,
paused/closed sessions, bounded cover geometry, seek availability and the persisted,
default-off external-artwork preference, plus YouTube category and video identity validation.
They do not request permissions, capture the screen or control real players.
Live acceptance and source-specific limitations are recorded in STATUS.md.
