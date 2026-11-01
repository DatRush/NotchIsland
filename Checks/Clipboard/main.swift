import AppKit
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
let history = ClipboardHistory(board: board, monitoring: false, shouldExclude: { false })
func write(_ text: String) { board.clearContents(); board.setString(text, forType: .string); history.capture() }
write("first"); write("second"); write("first")
precondition(history.entries.count == 2 && history.entries.first?.title == "first")
history.paused = true
write("private")
precondition(history.entries.count == 2)
history.paused = false
history.capture()
precondition(history.entries.count == 2)
let concealed = NSPasteboardItem()
concealed.setString("secret", forType: .string)
concealed.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
board.clearContents(); board.writeObjects([concealed]); history.capture()
precondition(history.entries.count == 2)
precondition(history.copy(history.entries[1]))
precondition(board.string(forType: .string) == "second")
history.capture(); precondition(history.entries.count == 2)
for i in 0..<60 { write("item \(i)") }
precondition(history.entries.count == 50)
history.remove(history.entries[0]); precondition(history.entries.count == 49)
history.clear(); history.capture(); precondition(history.entries.isEmpty)
print("PASS: duplicates, pause/resume, concealed data, copy, limit, removal, clear")

let textEntry = ClipboardEntry(title: "text", icon: "text.alignleft", items: [[.string: Data("Line 1\nLine 2".utf8)]])
precondition(textEntry.previewText == "Line 1\nLine 2")
let linkEntry = ClipboardEntry(title: "link", icon: "link", items: [[.URL: Data("https://example.com".utf8)]])
precondition(linkEntry.previewText == "https://example.com")
let fileEntry = ClipboardEntry(title: "files", icon: "doc", items: [[.fileURL: Data("file:///tmp/one.txt".utf8)], [.fileURL: Data("file:///tmp/two.txt".utf8)]])
precondition(fileEntry.fileURLs.map(\.lastPathComponent) == ["one.txt", "two.txt"])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = bitmap.representation(using: .png, properties: [:])!
let imageEntry = ClipboardEntry(title: "image", icon: "photo", items: [[.png: png]])
precondition(imageEntry.previewImage() != nil)
let badImage = ClipboardEntry(title: "bad", icon: "photo", items: [[.png: Data("invalid".utf8)]])
precondition(badImage.previewImage() == nil)
print("PASS: multiline preview, URL, file group, PNG thumbnail, invalid image")

precondition(ClipboardPrivacy.excludes("test.private", from: ["test.private"]))
precondition(!ClipboardPrivacy.excludes("test.other", from: ["test.private"]))
precondition(!ClipboardPrivacy.excludes(nil, from: ["test.private"]))
var excludedApp = true
let privateHistory = ClipboardHistory(board: board, monitoring: false, shouldExclude: { excludedApp })
board.clearContents(); board.setString("excluded value", forType: .string)
privateHistory.capture()
precondition(privateHistory.entries.isEmpty)
precondition(!privateHistory.canShowCurrentClipboard)
excludedApp = false
precondition(!privateHistory.canShowCurrentClipboard)
board.clearContents(); board.setString("allowed value", forType: .string)
privateHistory.capture()
precondition(privateHistory.entries.count == 1 && privateHistory.canShowCurrentClipboard)
print("PASS: excluded app, allowed app, hidden clipboard after app switch")

var clock = Date(timeIntervalSince1970: 1_800_000_000)
let expiring = ClipboardHistory(board: board, monitoring: false, now: { clock }, shouldExclude: { false })
board.clearContents(); board.setString("expires", forType: .string); expiring.capture()
let oldEntry = expiring.entries[0]
clock = clock.addingTimeInterval(12 * 60 * 60 - 1)
expiring.capture(); precondition(expiring.entries.count == 1)
expiring.paused = true
clock = clock.addingTimeInterval(1)
expiring.capture(); precondition(expiring.entries.isEmpty)
precondition(!expiring.copy(oldEntry))
expiring.paused = false
board.clearContents(); board.setString("sleep", forType: .string); expiring.capture()
clock = clock.addingTimeInterval(14 * 60 * 60)
expiring.expire(); precondition(expiring.entries.isEmpty)
print("PASS: before 12h, exact expiry during pause, expired copy rejected, simulated wake after 14h")
