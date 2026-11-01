import AppKit
import SwiftUI
import QuickLookThumbnailing

final class FileThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    private var request: QLThumbnailGenerator.Request?
    private var generation = UUID()

    func load(_ url: URL) {
        cancel()
        image = nil
        let key = url.standardizedFileURL.path as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Shelf copies are immutable. One 160px thumbnail serves both card sizes.
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 80), scale: 2, representationTypes: .thumbnail)
        self.request = request
        let generation = self.generation
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == generation else { return }
                self.request = nil
                guard let representation = representation else { return }
                let image = representation.nsImage
                Self.cache.setObject(image, forKey: key, cost: 160 * 160 * 4)
                self.image = image
            }
        }
    }
    func cancel() {
        generation = UUID()
        if let request = request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
    }
    deinit { if let request = request { QLThumbnailGenerator.shared.cancel(request) } }
}

struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @StateObject private var loader = FileThumbnailLoader()
    var body: some View {
        Image(nsImage: loader.image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().scaledToFit().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
            .onAppear { loader.load(url) }
            .onChange(of: url) { loader.load($0) }
            .onDisappear { loader.cancel() }
    }
}
