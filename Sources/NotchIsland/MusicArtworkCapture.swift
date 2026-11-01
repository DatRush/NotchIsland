import AppKit
import ScreenCaptureKit

struct MusicArtworkTarget: Equatable {
    let pid: pid_t
    let rect: CGRect
    static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
        rect.width >= 16 && rect.width <= 160 && rect.height >= 16 && rect.height <= 160 && abs(rect.width - rect.height) <= 4
    }
}
enum MusicArtworkCapture {
    // Only the explicitly identified square cover control, never a whole display.
    static func capture(_ target: MusicArtworkTarget, completion: @escaping (NSImage?) -> Void) {
        guard #available(macOS 14, *), CGPreflightScreenCaptureAccess(), MusicArtworkTarget.valid(target.rect) else { completion(nil); return }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.owningApplication?.processID == target.pid && $0.frame.contains(target.rect) }) else {
                    completion(nil); return
                }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: target.rect.minX - window.frame.minX, y: target.rect.minY - window.frame.minY,
                                           width: target.rect.width, height: target.rect.height)
                config.width = 160; config.height = 160; config.showsCursor = false
                config.scalesToFit = true
                config.destinationRect = CGRect(x: 0, y: 0, width: 160, height: 160)
                if #available(macOS 14.2, *) { config.ignoreShadowsSingleWindow = true }
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                completion(NSImage(cgImage: image, size: NSSize(width: 160, height: 160)))
            } catch { completion(nil) }
        }
    }
}
