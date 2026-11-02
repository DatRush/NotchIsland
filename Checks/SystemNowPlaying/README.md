# System Now Playing experiment

1. Build the upstream [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) separately and record the revision and macOS version.
2. Play a track in Yandex Music. Compare the active title with Control Center, decode the artwork, then pause and resume the same track.
3. Switch to YouTube in the user's browser and repeat. Verify that commands affect the video and the displayed artwork changes.
4. Consider app integration after both players pass. Verify packaging, fallback when the system exposes no session, and behavior after sleep before release.

Keep titles, artwork and raw session dumps out of Git.

## Run locally

On macOS 15.8.2 the standalone probe was built against upstream revision
`0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd`. Build the framework using the
upstream instructions. From the NotchIsland repository run:

```sh
swiftc Checks/SystemNowPlaying/inspect.swift -o /tmp/notchisland-inspect
/usr/bin/perl "$ADAPTER/bin/mediaremote-adapter.pl" "$FRAMEWORK" get | /tmp/notchisland-inspect
```

Set ADAPTER to the absolute upstream checkout path and FRAMEWORK to the absolute
built MediaRemoteAdapter.framework path. The inspector prints the current title,
player, playback state and decoded image dimensions locally. Repeat the read
after a few seconds if artwork is initially missing.

## Live results on macOS 15.8.2

Chrome playing YouTube and desktop Yandex Music both reported the track title.
For each player the probe observed playing, paused, then playing on the same
title after sending pause and play. The active bundle switched from Chrome to
Yandex when the user started the second player. The probe decoded 150 × 83
artwork from Chrome and 150 × 150 artwork from Yandex. Chrome artwork appeared
after the initial reads. Yandex artwork was missing from the first snapshot
after resume. During integration, retry missing artwork and keep a decoded
image only while its source and track still match.
