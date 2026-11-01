// Defers timer notices while an external screenshot picker owns the screen.
// Results/errors keep the notice pending until their panel is dismissed.
struct TimerNoticeGate {
    private(set) var capturing = false
    private(set) var pending = false
    mutating func beginCapture() { capturing = true }
    mutating func request() -> Bool {
        if capturing { pending = true; return false }
        return true
    }
    mutating func finishCapture(showingResult: Bool) -> Bool {
        capturing = false
        return !showingResult && consume()
    }
    mutating func consume() -> Bool {
        guard !capturing && pending else { return false }
        pending = false
        return true
    }
}
