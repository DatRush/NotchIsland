import AppKit
import SwiftUI

// Attach inside a horizontal ScrollView's content. Only consume vertical wheel
// events over that scroll view; native horizontal gestures remain untouched.
struct HorizontalWheelSupport: NSViewRepresentable {
    func makeNSView(context: Context) -> WheelBridge { WheelBridge() }
    func updateNSView(_ view: WheelBridge, context: Context) {}
    static func dismantleNSView(_ view: WheelBridge, coordinator: ()) { view.stop() }
}

final class WheelBridge: NSView {
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let window = self.window, event.window === window,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let scroll = self.enclosingScrollView,
                  let document = scroll.documentView else { return event }
            let clip = scroll.contentView
            let point = clip.convert(event.locationInWindow, from: nil)
            guard clip.bounds.contains(point) else { return event }
            let maximum = max(0, document.frame.width - clip.bounds.width)
            guard maximum > 0 else { return event }
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
            let x = min(maximum, max(0, clip.bounds.origin.x - delta))
            clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
            scroll.reflectScrolledClipView(clip)
            return nil
        }
    }
    func stop() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    deinit { stop() }
}
