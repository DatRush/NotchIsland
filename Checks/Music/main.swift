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

let video = "abcdefghijk"
let canonical = "<link rel=\"canonical\" href=\"https://www.youtube.com/watch?v=\(video)\">"
let musicTag = #"<meta itemprop="genre" content="Music">"#
check(YouTubeMusicFilter.classification(html: canonical + musicTag, id: video) == true, "Confirmed music")
check(YouTubeMusicFilter.classification(html: canonical + musicTag.replacingOccurrences(of: "Music", with: "Education"), id: video) == false, "Ordinary video hidden")
check(YouTubeMusicFilter.classification(html: canonical, id: video) == nil, "Missing category hidden")
check(YouTubeMusicFilter.classification(html: canonical + musicTag, id: "anotheritem") == nil, "Wrong video hidden")
check(YouTubeMusicFilter.videoID("https://example.org/watch?v=" + video) == nil, "Foreign tab ignored")
print("Music filter total: \(count) checks passed")

check(YouTubeMusicFilter.matches(tabTitle: "(1) coconut matcha. - YouTube", mediaTitle: "coconut matcha."), "YouTube notification count")
check(!YouTubeMusicFilter.matches(tabTitle: "Review of coconut matcha. - YouTube", mediaTitle: "coconut matcha."), "Unrelated title suffix rejected")
print("Music matching total: \(count) checks passed")

let entertainment = canonical + musicTag.replacingOccurrences(of: "Music", with: "Entertainment")
let collection = #"<meta property="og:description" content="A compilation of sounds for sleep.">"#
let musicKeyword = #"<meta property="og:video:tag" content="music">"#
check(YouTubeMusicFilter.classification(html: entertainment + collection + musicKeyword, id: video) == true, "Tagged music compilation")
check(YouTubeMusicFilter.classification(html: entertainment + musicKeyword, id: video) == false, "Music tag alone insufficient")
check(YouTubeMusicFilter.classification(html: entertainment + collection, id: video) == false, "Description alone insufficient")
print("Music compilation total: \(count) checks passed")

let browserVideo = sample("com.google.Chrome", true)
let appleTrack = sample("com.apple.Music", true)
let fallback = MusicPlayback.playbackSamples(running: [(browserVideo.source, 1), (appleTrack.source, 2)],
    system: { browserVideo }, read: { id, _ in
        precondition(id == appleTrack.source)
        return appleTrack
    }, allows: { $0.source != browserVideo.source })
check(fallback.0 == nil && fallback.1 == [appleTrack], "Rejected Chrome leaves playing Apple Music available")
let idle = MusicPlayback.playbackSamples(running: [], system: { fatalError("Unexpected system poll") },
    read: { _, _ in fatalError("Unexpected player poll") }, allows: { _ in true })
check(idle.0 == nil && idle.1.isEmpty, "No running players skips all adapters")
print("Music polling total: \(count) checks passed")
