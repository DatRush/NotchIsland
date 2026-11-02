import Foundation
import ImageIO

// Pipe a single adapter "get" response here. Decode the image locally.
struct Session: Decodable {
    let bundleIdentifier: String
    let title: String
    let playing: Bool
    let artworkData: Data?
}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let session = try JSONDecoder().decode(Session?.self, from: input) else {
        print("No active media session")
        exit(0)
    }
    print(session.bundleIdentifier, session.playing ? "playing" : "paused", session.title)
    if let bytes = session.artworkData,
       let source = CGImageSourceCreateWithData(bytes as CFData, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
        print("Artwork:", image.width, "×", image.height)
    } else {
        print("Artwork absent or unreadable")
    }
} catch {
    fputs("Invalid adapter response\n", stderr)
    exit(1)
}
