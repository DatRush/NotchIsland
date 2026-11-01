import Foundation
var count = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { guard value() else { fatalError(label) }; count += 1 }
func sample(_ source: String, _ playing: Bool) -> PlayingTrack { PlayingTrack(source: source, title: "Track", artist: "Artist", playing: playing, elapsed: 20, duration: 180) }
check(PlayingTrack.seconds("03:02") == 182, "Yandex duration parsed")
check(PlayingTrack.seconds("1:02:03") == 3723, "Long duration parsed")
check(PlayingTrack.seconds("live") == nil, "Live does not invent duration")
check(PlayingTrack.seconds("00:xx") == nil, "Invalid duration rejected")
check(MusicPlayback.choose([], current: nil, previous: [:]) == nil, "No player means no music")
check(MusicPlayback.choose([sample("a", true)], current: nil, previous: [:])?.source == "a", "Active player appears")
check(MusicPlayback.choose([sample("a", false)], current: nil, previous: [:]) == nil, "Previously paused player does not appear at startup")
check(MusicPlayback.choose([sample("a", false), sample("b", true)], current: "a", previous: ["a": true])?.source == "b", "Playing replaces paused source")
check(MusicPlayback.choose([sample("a", true), sample("b", true)], current: "a", previous: ["a": true, "b": false])?.source == "b", "Newly started source takes priority")
check(MusicPlayback.choose([sample("a", true), sample("b", true)], current: "b", previous: ["a": true, "b": true])?.source == "b", "Selection stable with two players")
check(MusicPlayback.choose([sample("a", false)], current: "a", previous: ["a": true])?.playing == false, "Pause removes active presentation")
check(MusicPlayback.choose([], current: "a", previous: ["a": true]) == nil, "Quit removes stale session")
print("Music: \(count) checks passed")
check(MusicArtworkTarget.valid(CGRect(x: 30, y: 50, width: 60, height: 60)), "Square cover allowed")
check(!MusicArtworkTarget.valid(CGRect(x: 0, y: 0, width: 1000, height: 700)), "Whole-window capture rejected")
check(!MusicArtworkTarget.valid(CGRect(x: 0, y: 0, width: 160, height: 40)), "Non-cover control rejected")
check(!MusicArtworkTarget.valid(CGRect(x: Double.infinity, y: 0, width: 60, height: 60)), "Invalid capture geometry rejected")
print("Music final: \(count) checks passed")

check(sample("com.apple.Music", true).canSeek, "Apple Music supports seek")
check(!sample("ru.yandex.desktop.music", true).canSeek, "Unsupported Yandex seek is not offered")
print("Music total: \(count) checks passed")

let suite = "NotchIsland.MusicChecks." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set(["source": "ru.yandex.desktop.music", "title": "Last track", "artist": "Artist"], forKey: "lastMusicTrack")
let restored = MusicPlayback(automatic: false, defaults: defaults)
check(restored.track?.title == "Last track", "Last track restored across launches")
check(!restored.isPlaying, "Restored track never pretends to be playing")
print("Music total: \(count) checks passed")

check(!restored.remoteArtworkEnabled, "External artwork is off by default")
defaults.set(true, forKey: RemoteArtworkPolicy.preferenceKey)
restored.remoteArtworkPreferenceChanged()
check(restored.remoteArtworkEnabled, "External artwork can be enabled explicitly")
let enabledRestored = MusicPlayback(automatic: false, defaults: defaults)
check(enabledRestored.remoteArtworkEnabled, "External artwork preference survives recreation")
defaults.set(false, forKey: RemoteArtworkPolicy.preferenceKey)
restored.remoteArtworkPreferenceChanged()
check(!restored.remoteArtworkEnabled, "External artwork can be disabled without restarting")
check(restored.track?.title == "Last track", "Privacy toggle preserves player information")
print("Music privacy total: \(count) checks passed")
