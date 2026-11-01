import AppKit
import Darwin
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--crash-fixture" {
    let workspace = try ScreenshotTemporaryDirectory(root: URL(fileURLWithPath: CommandLine.arguments[2]))
    try Data("synthetic capture".utf8).write(to: workspace.url.appendingPathComponent("capture.png"))
    kill(getpid(), SIGKILL)
    fatalError("SIGKILL did not terminate the fixture")
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("notch-shot-check-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = bitmap.representation(using: .png, properties: [:])!
let folder = root.appendingPathComponent("Папка снимков")
let first = try ScreenshotOutput.save(png, folder: folder, board: board)
let second = try ScreenshotOutput.save(png, folder: folder, board: board)
precondition(first != second)
let saved = try Data(contentsOf: second)
precondition(saved == board.data(forType: .png))
let image = NSBitmapImageRep(data: saved)!
precondition(image.pixelsWide == 4 && image.pixelsHigh == 3)
let change = board.changeCount
do { _ = try ScreenshotOutput.save(Data("invalid".utf8), folder: folder, board: board); fatalError("Invalid image accepted") } catch {}
precondition(board.changeCount == change)
do { _ = try ScreenshotOutput.save(png, folder: first, board: board); fatalError("Invalid directory accepted") } catch {}
precondition(board.changeCount == change)
print("PASS: folder creation, PNG image, unique names, clipboard matches file, invalid image and invalid directory preserve clipboard")

func result(_ status: Int32, _ diagnostic: String = "", _ reason: Process.TerminationReason = .exit) -> ScreenshotProcessResult {
    ScreenshotProcessResult(status: status, reason: reason, diagnostic: diagnostic)
}
for status: Int32 in [0, 1] {
    let empty = try result(status).image(file: nil, clipboard: nil)
    precondition(empty == nil)
}
let fileImage = try result(0).image(file: png, clipboard: Data([1]))
let controlImage = try result(0).image(file: nil, clipboard: png)
precondition(fileImage == png && controlImage == png)
for failure in [result(1, "screen capture permission denied"), result(0, "could not create image"), result(2), result(6, "", .uncaughtSignal)] {
    do { _ = try failure.image(file: nil, clipboard: png); fatalError("Failure accepted as cancellation or clipboard success") }
    catch { precondition(!error.localizedDescription.isEmpty) }
}
print("PASS: result classification, file priority, Control clipboard fallback, diagnostics and signals cannot be mistaken for cancellation")

let captureTemp = root.appendingPathComponent("capture-temp")
try FileManager.default.createDirectory(at: captureTemp, withIntermediateDirectories: true)
func runCapture(executable: String = "/bin/sh", script: String, onStart: () -> Void = {}, cancelImmediately: Bool = false) -> Result<URL?, Error> {
    let capture = ScreenshotCapture(board: board, temporaryRoot: captureTemp, executable: URL(fileURLWithPath: executable), arguments: { file in
        ["-c", script, "test-capture", file.path, second.path]
    })
    var outcome: Result<URL?, Error>?
    capture.start(folder: folder) { outcome = $0 }
    onStart()
    if cancelImmediately { capture.cancel() }
    let deadline = Date().addingTimeInterval(10)
    while outcome == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(outcome != nil)
    let leftovers = try! FileManager.default.contentsOfDirectory(atPath: captureTemp.path)
    precondition(leftovers.isEmpty, "All temporary files must be cleaned")
    return outcome!
}
let quiet = try runCapture(script: "exit 1").get()
precondition(quiet == nil)
let savedCapture = try runCapture(script: "cp \"$2\" \"$1\"").get()
precondition(savedCapture != nil)
for outcome in [runCapture(script: "echo 'capture failed' >&2; exit 1"), runCapture(script: "kill -TERM $$"), runCapture(script: "echo broken > \"$1\""), runCapture(executable: "/nonexistent/notch-test", script: "")] {
    if case .success = outcome { fatalError("Process failure swallowed") }
}
print("PASS: subprocess success, quiet exit, stderr failure, signal, invalid image, launch failure, temporary cleanup")

let clipboardCapture = try runCapture(script: "sleep 0.1", onStart: {
    board.clearContents()
    precondition(board.setData(png, forType: .png))
}).get()
precondition(clipboardCapture != nil)
let noNewImage = try runCapture(script: "exit 0").get()
precondition(noNewImage == nil, "An unchanged clipboard is not a capture")
let verboseFailure = runCapture(script: "dd if=/dev/zero bs=1024 count=100 >&2 2>/dev/null; exit 1")
if case .success = verboseFailure { fatalError("Verbose failure swallowed") }
print("PASS: changed named clipboard fallback, unchanged clipboard ignored, large stderr without pipe deadlock")

let beforeCancel = board.changeCount
let cancelled = try runCapture(script: "exec /bin/sleep 5", cancelImmediately: true).get()
precondition(cancelled == nil && board.changeCount == beforeCancel)
print("PASS: explicit cancellation returns no image, preserves clipboard and cleans temporary files")

func mode(_ url: URL) throws -> Int { (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue }
let pngMode = try mode(first)
precondition(pngMode == 0o600)
let recovery = root.appendingPathComponent("recovery")
try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
var active: ScreenshotTemporaryDirectory? = try ScreenshotTemporaryDirectory(root: recovery)
let activeURL = active!.url
let workspaceMode = try mode(activeURL)
precondition(workspaceMode == 0o700)
let future = Date().addingTimeInterval(25 * 3600)
try ScreenshotTemporaryDirectory.cleanAbandoned(in: recovery, now: future)
precondition(FileManager.default.fileExists(atPath: activeURL.path), "Active lock must survive cleanup")
active = nil
try ScreenshotTemporaryDirectory.cleanAbandoned(in: recovery)
precondition(FileManager.default.fileExists(atPath: activeURL.path), "Recent abandoned folder must be retained")
try ScreenshotTemporaryDirectory.cleanAbandoned(in: recovery, now: future)
precondition(!FileManager.default.fileExists(atPath: activeURL.path), "Old unlocked folder must be cleaned")
var unknown: ScreenshotTemporaryDirectory? = try ScreenshotTemporaryDirectory(root: recovery)
let unknownURL = unknown!.url
try Data("keep".utf8).write(to: unknownURL.appendingPathComponent("user-file.txt"))
unknown = nil
let external = root.appendingPathComponent("external-target")
try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
let linked = recovery.appendingPathComponent("NotchIsland-Capture-" + UUID().uuidString)
try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: external)
try ScreenshotTemporaryDirectory.cleanAbandoned(in: recovery, now: future)
precondition(FileManager.default.fileExists(atPath: unknownURL.path))
precondition(FileManager.default.fileExists(atPath: external.path))
precondition(FileManager.default.fileExists(atPath: linked.path))
let crashRoot = root.appendingPathComponent("crash-recovery")
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
child.arguments = ["--crash-fixture", crashRoot.path]
try child.run(); child.waitUntilExit()
precondition(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL)
let remains = try FileManager.default.contentsOfDirectory(atPath: crashRoot.path)
precondition(remains.count == 1)
try ScreenshotTemporaryDirectory.cleanAbandoned(in: crashRoot, now: future)
let cleaned = try FileManager.default.contentsOfDirectory(atPath: crashRoot.path)
precondition(cleaned.isEmpty, "SIGKILL releases the lock; later cleanup removes synthetic remnants")
print("PASS: private PNG/workspace modes, active/recent protection, stale cleanup, unknown/symlink preservation and real SIGKILL recovery")

let unmarked = recovery.appendingPathComponent("NotchIsland-Capture-" + UUID().uuidString)
try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: true)
try Data("legacy fixture".utf8).write(to: unmarked.appendingPathComponent("capture.png"))
let expectedOriginalPNG = try Data(contentsOf: first)
let fakeLock = recovery.appendingPathComponent("NotchIsland-Capture-" + UUID().uuidString)
try FileManager.default.createDirectory(at: fakeLock, withIntermediateDirectories: true)
try FileManager.default.createSymbolicLink(at: fakeLock.appendingPathComponent(".capture-lock"), withDestinationURL: first)
try ScreenshotTemporaryDirectory.cleanAbandoned(in: recovery, now: future)
precondition(FileManager.default.fileExists(atPath: unmarked.path))
precondition(FileManager.default.fileExists(atPath: fakeLock.path))
let originalPNG = try Data(contentsOf: first)
precondition(originalPNG == expectedOriginalPNG)
print("PASS: unmarked legacy folders and symbolic lock targets preserved")
