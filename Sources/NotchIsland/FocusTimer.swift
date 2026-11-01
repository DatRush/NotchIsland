import AppKit
import SwiftUI
import Darwin

// Continuous monotonic time includes sleep and is independent of wall-clock edits.
private func focusTime() -> TimeInterval {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
}

final class FocusTimer: ObservableObject {
    enum State { case idle, running, paused, completed }
    @Published private(set) var state: State = .idle
    static let maximumDuration = 24 * 60 * 60 - 1
    static let recentKey = "focusRecentDurations"
    static let recentLimit = 6
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var durationSeconds = 0
    @Published private(set) var remainingDuration: TimeInterval = 0
    @Published private(set) var recentDurations: [Int]
    @Published var hours = "00"
    @Published var minutes = "25"
    @Published var seconds = "00"
    private let defaults: UserDefaults
    var onExpired: (() -> Void)?
    private var deadline: TimeInterval?
    private var pausedRemaining: TimeInterval = 0
    private let now: () -> TimeInterval
    private let automaticTicks: Bool
    private var ticker: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(now: @escaping () -> TimeInterval = focusTime, automaticTicks: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen = Set<Int>()
        recentDurations = Array((defaults.array(forKey: Self.recentKey) as? [Int] ?? [])
            .filter { (1...Self.maximumDuration).contains($0) && seen.insert($0).inserted }
            .prefix(Self.recentLimit))
        self.now = now
        self.automaticTicks = automaticTicks
        if let latest = recentDurations.first { selectDuration(latest) }
        if automaticTicks {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
    }
    deinit {
        ticker?.invalidate()
        if let observer = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    var isVisible: Bool { state != .idle }
    var timeText: String { Self.format(remainingSeconds) }
    var progress: Double { durationSeconds > 0 ? min(1, max(0, remainingDuration / Double(durationSeconds))) : 0 }
    var compactTimeText: String {
        remainingSeconds >= 3600 ? timeText : String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
    var compactLayout: FocusCompactLayout { FocusCompactLayout(text: compactTimeText, active: isVisible) }
    var selectedDuration: Int {
        guard let h = Int(hours.isEmpty ? "0" : hours), (0...23).contains(h),
              let m = Int(minutes.isEmpty ? "0" : minutes), (0...59).contains(m),
              let s = Int(seconds.isEmpty ? "0" : seconds), (0...59).contains(s) else { return 0 }
        return h * 3600 + m * 60 + s
    }
    static func format(_ duration: Int) -> String {
        if duration >= 3600 {
            return String(format: "%d:%02d:%02d", duration / 3600, (duration / 60) % 60, duration % 60)
        }
        return String(format: "%02d:%02d", duration / 60, duration % 60)
    }
    func selectDuration(_ duration: Int) {
        guard (1...Self.maximumDuration).contains(duration) else { return }
        hours = String(format: "%02d", duration / 3600)
        minutes = String(format: "%02d", (duration / 60) % 60)
        seconds = String(format: "%02d", duration % 60)
    }
    func start(seconds: Int) {
        guard state == .idle || state == .completed, (1...Self.maximumDuration).contains(seconds) else { return }
        selectDuration(seconds)
        recentDurations.removeAll { $0 == seconds }
        recentDurations.insert(seconds, at: 0)
        recentDurations = Array(recentDurations.prefix(Self.recentLimit))
        defaults.set(recentDurations, forKey: Self.recentKey)
        durationSeconds = seconds
        remainingSeconds = seconds
        remainingDuration = Double(seconds)
        deadline = now() + Double(remainingSeconds)
        state = .running
        startTicker()
    }
    func pause() {
        refresh()
        guard state == .running, let deadline else { return }
        pausedRemaining = max(0, deadline - now())
        remainingDuration = pausedRemaining
        self.deadline = nil
        state = .paused
        stopTicker()
    }
    func resume() {
        guard state == .paused else { return }
        deadline = now() + pausedRemaining
        state = .running
        startTicker()
        refresh()
    }
    func finish() {
        guard state == .running || state == .paused else { return }
        complete()
    }
    func reset() {
        stopTicker()
        deadline = nil
        pausedRemaining = 0
        remainingSeconds = 0
        remainingDuration = 0
        durationSeconds = 0
        state = .idle
    }
    func refresh() {
        guard state == .running, let deadline else { return }
        let remaining = max(0, deadline - now())
        if remaining <= 0 { complete(); onExpired?(); return }
        remainingDuration = remaining
        let seconds = Int(ceil(remaining))
        if remainingSeconds != seconds { remainingSeconds = seconds }
    }
    private func complete() {
        stopTicker()
        deadline = nil
        pausedRemaining = 0
        remainingSeconds = 0
        remainingDuration = 0
        state = .completed
    }
    private func startTicker() {
        stopTicker()
        guard automaticTicks else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
}

// Geometry uses macOS's unobscured areas rather than a fixed camera width.
// https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc
struct FocusIslandGeometry {
    let notchWidth: CGFloat
    let headerHeight: CGFloat
    let centerX: CGFloat

    init(frame: CGRect, leftArea: CGRect?, rightArea: CGRect?, topInset: CGFloat) {
        if topInset > 0, let leftArea, let rightArea,
           rightArea.minX > leftArea.maxX,
           leftArea.maxX >= frame.minX, rightArea.minX <= frame.maxX {
            notchWidth = rightArea.minX - leftArea.maxX
            centerX = (leftArea.maxX + rightArea.minX) / 2
            headerHeight = max(32, topInset)
        } else {
            notchWidth = 160
            headerHeight = 32
            centerX = frame.midX
        }
    }
    func compactSize(layout: FocusCompactLayout) -> CGSize {
        CGSize(width: notchWidth + layout.timeWidth + layout.symbolWidth, height: headerHeight)
    }
}

struct FocusCompactLayout: Equatable {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    let timeWidth: CGFloat
    let symbolWidth: CGFloat
    var centerOffset: CGFloat { (symbolWidth - timeWidth) / 2 }

    init(text: String, active: Bool) {
        // Match SwiftUI's actual font; reserve no unused hour digits.
        timeWidth = active ? ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 20 : 0
        symbolWidth = active ? 36 : 0
    }
}

struct FocusDurationField: View {
    let title: String
    let maximum: Int
    @Binding var text: String

    private var value: Int { Int(text) ?? 0 }
    private func step(_ delta: Int) {
        text = String(format: "%02d", min(maximum, max(0, value + delta)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundColor(.gray)
            HStack(spacing: 2) {
                TextField("00", text: Binding(get: { text }, set: { input in
                    let digits = String(input.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    text = digits.isEmpty ? "" : String(min(maximum, Int(digits) ?? 0))
                }))
                .textFieldStyle(.plain)
                .font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit()
                .accessibilityLabel(title)
                VStack(spacing: 5) {
                    Button { step(1) } label: { Image(systemName: "chevron.up").frame(width: 20, height: 12) }
                        .disabled(value >= maximum).accessibilityLabel(L("Увеличить: ", "Increase: ") + title)
                    Button { step(-1) } label: { Image(systemName: "chevron.down").frame(width: 20, height: 12) }
                        .disabled(value <= 0).accessibilityLabel(L("Уменьшить: ", "Decrease: ") + title)
                }.font(.system(size: 8, weight: .semibold)).buttonStyle(.plain)
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FocusTimerView: View {
    @ObservedObject var timer: FocusTimer
    var body: some View {
        VStack(spacing: 9) {
            if timer.state == .idle {
                HStack {
                    Text(L("Таймер", "Timer")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { timer.start(seconds: timer.selectedDuration) } label: {
                        Label(L("Начать", "Start"), systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundColor(.black)
                            .background(Color.white.opacity(timer.selectedDuration > 0 ? 1 : 0.3), in: Capsule())
                    }.buttonStyle(.plain).disabled(timer.selectedDuration == 0)
                }
                HStack(spacing: 8) {
                    FocusDurationField(title: L("Часы", "Hours"), maximum: 23, text: $timer.hours)
                    FocusDurationField(title: L("Минуты", "Minutes"), maximum: 59, text: $timer.minutes)
                    FocusDurationField(title: L("Секунды", "Seconds"), maximum: 59, text: $timer.seconds)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("ПОСЛЕДНИЕ", "RECENT")).font(.system(size: 9, weight: .medium)).foregroundColor(.gray)
                    if timer.recentDurations.isEmpty {
                        Text(L("Здесь появятся запущенные таймеры", "Recently started timers will appear here"))
                            .font(.system(size: 11)).foregroundColor(.gray).frame(height: 25)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(timer.recentDurations, id: \.self) { duration in
                                    Button { timer.selectDuration(duration) } label: {
                                        Text(FocusTimer.format(duration)).monospacedDigit()
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.white.opacity(0.10), in: Capsule())
                                    }.buttonStyle(.plain).help(L("Выбрать ", "Select ") + FocusTimer.format(duration))
                                }
                            }
                        }.frame(height: 27)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 18) {
                    FocusProgressRing(timer: timer).frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.state == .completed ? L("Таймер завершён", "Timer finished") : timer.state == .paused ? L("На паузе", "Paused") : L("Таймер", "Timer"))
                            .font(.system(size: 12)).foregroundColor(.gray)
                        Text(timer.timeText).font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }.padding(.top, 10)
                HStack(spacing: 10) {
                    if timer.state == .completed {
                        control(L("Готово", "Done"), icon: "checkmark", primary: true) { timer.reset() }
                    } else {
                        control(L("Завершить", "Finish"), icon: "xmark", primary: false) { timer.finish() }
                        control(timer.state == .paused ? L("Продолжить", "Resume") : L("Пауза", "Pause"),
                                icon: timer.state == .paused ? "play.fill" : "pause.fill", primary: true) {
                            if timer.state == .paused { timer.resume() } else { timer.pause() }
                        }
                    }
                }.padding(.top, 6)
            }
        }.padding(.top, 5)
            .help(L("Сон Mac учитывается. При выходе текущая сессия сбрасывается; последние длительности сохраняются.", "The timer includes Mac sleep time. Quitting resets the current session; recent durations are saved."))
    }
    private func control(_ title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundColor(primary ? .black : .white)
                .background(primary ? Color.white : Color.white.opacity(0.13), in: Capsule())
        }.buttonStyle(.plain)
    }
}

// Arc and hand share one animatable value, so both follow the same remaining time.
struct FocusDial: View, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            let line: CGFloat = size > 30 ? 3 : 2.5
            ZStack {
                Circle().stroke(Color.white.opacity(0.13), lineWidth: line)
                Circle().trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Capsule().fill(Color.white)
                    .frame(width: line, height: size * 0.29)
                    .offset(y: -size * 0.15)
                    .rotationEffect(.degrees(360 * progress))
            }.padding(line / 2)
        }
    }
}

struct FocusProgressRing: View {
    @ObservedObject var timer: FocusTimer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            FocusDial(progress: timer.progress)
                .opacity(timer.state == .completed ? 0 : 1)
                .animation(reduceMotion || timer.state != .running ? nil : .linear(duration: 0.25), value: timer.progress)
            if timer.state == .completed {
                Image(systemName: "checkmark.circle").resizable().scaledToFit().padding(1)
            } else if timer.state == .paused {
                // Preserve the remaining arc, replace the hand with an unambiguous pause mark.
                Circle().fill(Color.black).padding(5)
                Image(systemName: "pause.fill").font(.system(size: 8, weight: .semibold))
            }
        }.foregroundColor(.white).accessibilityHidden(true)
    }
}

struct FocusTimerIndicator: View {
    @ObservedObject var timer: FocusTimer
    var body: some View {
        Text(timer.compactTimeText)
            .font(Font(FocusCompactLayout.font)).foregroundColor(.white)
            .fixedSize()
            .accessibilityLabel(timer.state == .completed ? L("Таймер завершён", "Timer finished") : L("Таймер: ", "Timer: ") + timer.timeText + (timer.state == .paused ? L(", пауза", ", paused") : ""))
    }
}
