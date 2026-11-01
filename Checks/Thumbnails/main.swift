import AppKit
import CoreGraphics
let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-thumbnails-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let pdf = root.appendingPathComponent("preview.pdf")
var box = CGRect(x: 0, y: 0, width: 200, height: 280)
let context = CGContext(pdf as CFURL, mediaBox: &box, nil)!
context.beginPDFPage(nil)
context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
context.fill(CGRect(x: 20, y: 20, width: 160, height: 240))
context.endPDFPage(); context.closePDF()
let loader = FileThumbnailLoader()
loader.load(pdf)
let deadline = Date().addingTimeInterval(15)
while loader.image == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
guard loader.image != nil else { fatalError("Quick Look did not produce the PDF thumbnail") }
loader.load(root.appendingPathComponent("missing.pdf"))
precondition(loader.image == nil)
loader.load(pdf)
precondition(loader.image != nil, "Cached result should be immediate")
loader.cancel()
print("PASS: PDF thumbnail, missing-file fallback, thumbnail cache")
