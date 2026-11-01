var count = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    precondition(value(), label); count += 1
}
for outcome in ["screenshot", "gpt", "failure", "cancel"] {
    var gate = TimerNoticeGate()
    gate.beginCapture()
    check(!gate.request() && gate.pending, "Expiry must not open hidden panel during \(outcome)")
    check(!gate.consume(), "External dismissal during capture cannot consume notice")
    let showingResult = outcome != "cancel"
    check(gate.finishCapture(showingResult: showingResult) == !showingResult, "Cancellation shows notice; results keep focus")
    check(!gate.capturing, "Capture always ends")
    check(gate.consume() == showingResult, "Closing result consumes deferred notice exactly once")
    check(!gate.consume(), "No repeated notice after dismissal")
}
var gate = TimerNoticeGate()
gate.beginCapture()
check(!gate.finishCapture(showingResult: false), "Cancellation without expiry creates no notice")
check(gate.request(), "Ordinary expiry can display immediately")
print("TimerNotice: \(count) checks passed")
