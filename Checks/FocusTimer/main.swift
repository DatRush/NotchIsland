import Foundation
import CoreGraphics

var clock: TimeInterval = 100
let suite = "NotchIsland.FocusChecks." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let timer = FocusTimer(now: { clock }, automaticTicks: false, defaults: defaults)
var count = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    guard value() else { fatalError(label) }
    count += 1
}
check(timer.state == .idle && !timer.isVisible, "Initially hidden")
timer.start(seconds: 0)
check(timer.state == .idle, "Reject zero")
timer.start(seconds: FocusTimer.maximumDuration + 1)
check(timer.state == .idle, "Reject excessive duration")
timer.start(seconds: 1500)
check(timer.remainingSeconds == 1500 && timer.timeText == "25:00", "Initial duration")
timer.start(seconds: 300)
check(timer.remainingSeconds == 1500, "Do not replace active session")
clock += 0.2
timer.refresh()
check(timer.remainingSeconds == 1500, "Round up partial second")
clock += 10
timer.pause()
check(timer.state == .paused && timer.remainingSeconds == 1490, "Pause")
clock += 3600
timer.refresh()
check(timer.remainingSeconds == 1490, "Pause survives sleep")
timer.resume()
clock += 1489.7
timer.refresh()
check(timer.state == .running && timer.remainingSeconds == 1, "Resume preserves fraction")
clock += 0.2
timer.refresh()
check(timer.state == .completed && timer.remainingSeconds == 0 && timer.isVisible, "Natural completion")
timer.pause(); timer.resume(); timer.refresh()
check(timer.state == .completed, "Completion stable")
timer.reset()
check(timer.state == .idle && !timer.isVisible, "Dismiss")
timer.start(seconds: 60)
clock += 7200
timer.refresh()
check(timer.state == .completed, "Sleep past deadline")
timer.start(seconds: 60)
clock += 60
timer.pause()
check(timer.state == .completed, "Pause at deadline completes")
timer.start(seconds: FocusTimer.maximumDuration)
check(timer.timeText == "23:59:59", "Maximum duration")
timer.finish()
check(timer.state == .completed, "Manual completion")
timer.reset(); timer.start(seconds: 300); timer.pause(); timer.finish()
check(timer.state == .completed, "Finish paused session")
timer.reset(); timer.start(seconds: 60); timer.reset(); clock += 600; timer.refresh()
check(timer.state == .idle && timer.remainingSeconds == 0, "Reset invalidates deadline")
check(timer.selectedDuration == 60, "Selection survives reset")
timer.start(seconds: 1)
check(timer.timeText == "00:01" && timer.progress == 1, "One second timer")
clock += 1; timer.refresh()
check(timer.state == .completed && timer.progress == 0, "One second completion")
timer.reset(); timer.start(seconds: 3661)
check(timer.timeText == "1:01:01", "Hour minute second formatting")
clock += 62; timer.refresh()
check(timer.timeText == "59:59", "Transition from hours to minutes")
check(timer.progress > 0 && timer.progress < 1, "Progress fraction")
timer.reset()
timer.hours = "02"; timer.minutes = "03"; timer.seconds = "04"
check(timer.selectedDuration == 7384, "All three components")
timer.selectDuration(7384)
check(timer.hours == "02" && timer.minutes == "03" && timer.seconds == "04", "Selection decomposes duration")
timer.hours = "24"
check(timer.selectedDuration == 0, "Invalid hour rejected")
timer.hours = "00"; timer.minutes = "60"
check(timer.selectedDuration == 0, "Invalid minute rejected")
timer.minutes = "00"; timer.seconds = "60"
check(timer.selectedDuration == 0, "Invalid second rejected")
timer.hours = ""; timer.minutes = ""; timer.seconds = ""
check(timer.selectedDuration == 0, "Empty components disable start")
timer.start(seconds: -1)
check(timer.state == .idle, "Negative duration rejected")
for duration in [10, 20, 30, 40, 50, 60, 70] {
    timer.reset(); timer.start(seconds: duration)
}
check(timer.recentDurations == [70, 60, 50, 40, 30, 20], "Bounded newest first history")
timer.reset(); timer.start(seconds: 40)
check(timer.recentDurations == [40, 70, 60, 50, 30, 20], "Reuse promotes without duplicates")
timer.start(seconds: 100)
check(timer.recentDurations.first == 40, "Rejected start does not alter history")
timer.reset(); timer.selectDuration(70)
check(timer.state == .idle && timer.selectedDuration == 70 && timer.recentDurations.first == 40, "History selection does not launch or reorder")
let restored = FocusTimer(now: { clock }, automaticTicks: false, defaults: defaults)
check(restored.recentDurations == timer.recentDurations && restored.selectedDuration == 40, "History and latest selection restored")
check(restored.state == .idle, "Restoring history does not resume previous timer")
defaults.set([0, -1, 10, 10, FocusTimer.maximumDuration + 1, 20], forKey: FocusTimer.recentKey)
let sanitized = FocusTimer(automaticTicks: false, defaults: defaults)
check(sanitized.recentDurations == [10, 20], "Invalid and duplicate persisted durations excluded")
defaults.set("malformed", forKey: FocusTimer.recentKey)
let malformed = FocusTimer(automaticTicks: false, defaults: defaults)
check(malformed.recentDurations.isEmpty, "Malformed history safely ignored")
check(malformed.selectedDuration == 1500, "Default duration without invented recent timers")

let frame = CGRect(x: 100, y: 0, width: 1500, height: 900)
let geometry = FocusIslandGeometry(frame: frame,
    leftArea: CGRect(x: 100, y: 868, width: 650, height: 32),
    rightArea: CGRect(x: 950, y: 868, width: 650, height: 32), topInset: 32)
check(geometry.notchWidth == 200 && geometry.centerX == 850, "Physical camera bounds")
let layout = FocusCompactLayout(text: "2:50", active: true)
let size = geometry.compactSize(layout: layout)
let left = geometry.centerX + layout.centerOffset - size.width / 2
check(left + layout.timeWidth == 750, "Time ends at left camera edge")
check(left + size.width - layout.symbolWidth == 950, "Dial starts at right camera edge")
check(size.height == 32 && geometry.compactSize(layout: FocusCompactLayout(text: "0:00", active: false)).width == 200, "No strip below camera")
let fallback = FocusIslandGeometry(frame: frame, leftArea: nil, rightArea: nil, topInset: 0)
check(fallback.notchWidth == 160 && fallback.centerX == frame.midX, "Safe fallback without notch metadata")
let scaled = FocusIslandGeometry(frame: frame,
    leftArea: CGRect(x: 100, y: 862, width: 640, height: 38),
    rightArea: CGRect(x: 960, y: 862, width: 640, height: 38), topInset: 38)
check(scaled.headerHeight == 38 && scaled.notchWidth == 220, "Scaled display geometry")
let shortLayout = FocusCompactLayout(text: "9:59", active: true)
let mediumLayout = FocusCompactLayout(text: "10:00", active: true)
let hourLayout = FocusCompactLayout(text: "1:00:00", active: true)
check(shortLayout.timeWidth < mediumLayout.timeWidth && mediumLayout.timeWidth < hourLayout.timeWidth, "Width follows number of digits")
check(shortLayout == FocusCompactLayout(text: "2:50", active: true), "Same-length digits do not resize")
check(shortLayout.timeWidth + shortLayout.symbolWidth < 128, "Short timer is smaller than previous fixed wing")
for text in ["0:00", "2:50", "10:00", "1:00:00", "23:59:59"] {
    let wings = FocusCompactLayout(text: text, active: true)
    let width = geometry.compactSize(layout: wings).width
    let x = geometry.centerX + wings.centerOffset - width / 2
    check(x + wings.timeWidth == 750 && x + width - wings.symbolWidth == 950, "Camera remains aligned for " + text)
}
timer.reset(); timer.start(seconds: 10)
clock += 0.25; timer.refresh()
check(timer.remainingSeconds == 10 && abs(timer.progress - 0.975) < 0.00001, "Progress changes within a displayed second")
timer.pause()
let frozenProgress = timer.progress
clock += 5; timer.refresh()
check(timer.progress == frozenProgress, "Dial freezes on pause")
timer.resume(); clock += 9; timer.refresh()
check(abs(timer.progress - 0.075) < 0.00001 && timer.compactTimeText == "0:01", "Near completion leaves only a short arc")
clock += 1; timer.refresh()
check(timer.progress == 0 && timer.state == .completed, "Completion clears arc")
print("FocusTimer: \(count) checks passed")

var expirations = 0
timer.onExpired = { expirations += 1 }
timer.reset(); timer.start(seconds: 2)
clock += 3; timer.refresh(); timer.refresh()
check(expirations == 1, "Natural expiry notifies exactly once")
timer.reset(); timer.start(seconds: 20); timer.finish()
check(expirations == 1, "Manual finish does not show automatic notice")
print("FocusTimer total: \(count) checks passed")
