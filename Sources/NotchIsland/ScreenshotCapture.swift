import AppKit
import Darwin

/// Only marked capture folders are eligible for recovery cleanup. The lock protects
/// active captures, including another running instance. Unrecognized files are kept.
final class ScreenshotTemporaryDirectory {
    let url: URL
    private var lock: Int32 = -1
    init(root: URL) throws {
        url = root.appendingPathComponent("NotchIsland-Capture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        lock = open(url.appendingPathComponent(".capture-lock").path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else {
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock)
            lock = -1
            try? FileManager.default.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown)
        }
    }
    deinit { if lock >= 0 { close(lock) } }
    func remove() { try? FileManager.default.removeItem(at: url) }
    static func cleanAbandoned(in root: URL, now: Date = Date()) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return }
        let folders = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for folder in folders {
            let prefix = "NotchIsland-Capture-"
            guard folder.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(folder.lastPathComponent.dropFirst(prefix.count))) != nil,
                  let attributes = try? manager.attributesOfItem(atPath: folder.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) >= 24 * 3600 else { continue }
            let descriptor = open(folder.appendingPathComponent(".capture-lock").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, metadata.st_uid == getuid(),
                  metadata.st_mode & S_IFMT == S_IFREG,
                  flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
            let children = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let recognized = Set(["capture.png", "stderr.txt", ".capture-lock"])
            guard children.allSatisfy({ child in
                guard recognized.contains(child.lastPathComponent),
                      let info = try? manager.attributesOfItem(atPath: child.path) else { return false }
                return info[.type] as? FileAttributeType == .typeRegular &&
                    (info[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
            }) else { continue }
            try manager.removeItem(at: folder)
        }
    }
}

struct ScreenshotOutput {
    static func save(_ data: Data, folder: URL, board: NSPasteboard = .general) throws -> URL {
        guard let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = L("Снимок \(formatter.string(from: Date())) \(UUID().uuidString.prefix(8)).png", "Screenshot \(formatter.string(from: Date())) \(UUID().uuidString.prefix(8)).png")
        let file = folder.appendingPathComponent(name)
        let descriptor = open(file.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try output.write(contentsOf: png)
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        board.clearContents()
        guard board.setData(png, forType: .png) else { throw CocoaError(.fileWriteUnknown) }
        return file
    }
}

struct ScreenshotProcessResult {
    let status: Int32
    let reason: Process.TerminationReason
    let diagnostic: String

    func image(file: Data?, clipboard: Data?) throws -> Data? {
        let detail = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        // Compatibility fallback until interactive exit codes are verified on-device:
        // quiet normal exits 0/1 without an image remain cancellation-like. A silent
        // failure with that same tuple is ambiguous; do not claim this proves Esc.
        // Signals, diagnostics and other statuses must never silently dismiss errors.
        guard reason == .exit, (status == 0 || status == 1), detail.isEmpty else {
            throw CaptureFailure(message: L("Не удалось сделать снимок. Повторите захват и проверьте разрешение на запись экрана.", "Could not take a screenshot. Try again and check Screen Recording permission."), detail: detail.isEmpty ? L("Код завершения: \(status)", "Exit code: \(status)") : String(detail.prefix(400)))
        }
        return file ?? clipboard
    }
}

struct CaptureFailure: LocalizedError {
    let message: String
    let detail: String
    var errorDescription: String? { message + " " + detail }
}

final class ScreenshotCapture {
    private var process: Process?
    private var rightClickMonitor: Any?
    private var localRightClickMonitor: Any?
    private var cancelled = false

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let process, process.isRunning else { return }
        cancelled = true
        process.terminate()
    }

    private func removeMonitors() {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        if let localRightClickMonitor { NSEvent.removeMonitor(localRightClickMonitor) }
        rightClickMonitor = nil
        localRightClickMonitor = nil
    }
    private let board: NSPasteboard
    private let temporaryRoot: URL
    private let executable: URL
    private let arguments: (URL) -> [String]

    init(board: NSPasteboard = .general,
         temporaryRoot: URL = FileManager.default.temporaryDirectory,
         executable: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"),
         arguments: @escaping (URL) -> [String] = { ["-i", "-s", "-x", "-t", "png", $0.path] }) {
        self.board = board
        self.temporaryRoot = temporaryRoot
        self.executable = executable
        self.arguments = arguments
        // A crash can bypass terminationHandler; retry cleanup at the next launch.
        try? ScreenshotTemporaryDirectory.cleanAbandoned(in: temporaryRoot)
    }

    func start(folder: URL, completion: @escaping (Result<URL?, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard process == nil else { return }
        let workspace: ScreenshotTemporaryDirectory
        do { workspace = try ScreenshotTemporaryDirectory(root: temporaryRoot) }
        catch { completion(.failure(error)); return }
        let temporary = workspace.url
        let file = temporary.appendingPathComponent("capture.png")
        let diagnostics = temporary.appendingPathComponent("stderr.txt")
        // A file avoids filling a pipe and deadlocking the child before termination.
        let errors: FileHandle
        do {
            try Data().write(to: diagnostics)
            errors = try FileHandle(forWritingTo: diagnostics)
        } catch {
            workspace.remove()
            completion(.failure(error)); return
        }
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments(file)
        task.standardError = errors
        let priorChange = board.changeCount
        cancelled = false
        process = task
        task.terminationHandler = { [self] task in
            DispatchQueue.main.async { [self] in
                self.removeMonitors()
                self.process = nil
                defer {
                    try? errors.close()
                    workspace.remove()
                }
                if self.cancelled { completion(.success(nil)); return }
                do {
                    let diagnostic = String(decoding: try Data(contentsOf: diagnostics), as: UTF8.self)
                    let result = ScreenshotProcessResult(status: task.terminationStatus, reason: task.terminationReason, diagnostic: diagnostic)
                    let data = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
                    // Control-drag sends its image to the clipboard instead of a file.
                    let clipboard = board.changeCount != priorChange ? board.data(forType: .png) ?? board.data(forType: .tiff) : nil
                    guard let image = try result.image(file: data, clipboard: clipboard) else {
                        completion(.success(nil)); return
                    }
                    completion(.success(try ScreenshotOutput.save(image, folder: folder, board: board)))
                } catch { completion(.failure(error)) }
            }
        }
        do {
            try task.run()
            rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in self?.cancel() }
            localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
                self?.cancel()
                return nil
            }
        }
        catch {
            removeMonitors()
            process = nil
            task.terminationHandler = nil
            try? errors.close()
            workspace.remove()
            completion(.failure(error))
        }
    }
}
