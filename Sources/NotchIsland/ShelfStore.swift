import Foundation

struct ShelfRecord: Codable {
    let folder: UUID
    let filename: String
    let addedAt: Date
}

// Each owned UUID directory contains one copied object and its small manifest.
// Original paths are never used for removal.
final class ShelfStore {
    let root: URL
    private(set) var records: [ShelfRecord] = []
    private let now: () -> Date
    private let lifetime: () -> TimeInterval
    private let manager = FileManager.default
    private let manifestName = ".shelf-entry.json"
    var files: [URL] { records.map { url(for: $0) } }

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchIsland/PrototypeShelf", isDirectory: true), now: @escaping () -> Date = Date.init, lifetime: @escaping () -> TimeInterval = {
        let hours = UserDefaults.standard.integer(forKey: "shelfHours")
        return TimeInterval([6, 12, 24].contains(hours) ? hours : 24) * 3600
    }) {
        self.root = root.standardizedFileURL
        self.now = now
        self.lifetime = lifetime
    }
    private func url(for record: ShelfRecord) -> URL {
        root.appendingPathComponent(record.folder.uuidString, isDirectory: true).appendingPathComponent(record.filename)
    }
    private func valid(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && name != manifestName
    }
    private func prepareRoot() throws {
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: root.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CocoaError(.fileWriteInvalidFileName) }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    func restore() throws {
        try prepareRoot()
        var restored: [ShelfRecord] = []
        for directory in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]) {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let manifest = directory.appendingPathComponent(manifestName)
            let record: ShelfRecord
            if manager.fileExists(atPath: manifest.path) {
                // A damaged manifest is left untouched; do not guess its retention date.
                guard let decoded = try? JSONDecoder().decode(ShelfRecord.self, from: Data(contentsOf: manifest)), decoded.folder == id, valid(decoded.filename) else { continue }
                record = decoded
            } else {
                // Adopt copies made by the earlier prototype without touching their originals.
                let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                guard children.count == 1, let child = children.first, valid(child.lastPathComponent) else { continue }
                record = ShelfRecord(folder: id, filename: child.lastPathComponent, addedAt: values.creationDate ?? now())
                try save(record)
            }
            guard manager.fileExists(atPath: url(for: record).path) else { continue }
            restored.append(record)
        }
        records = restored.sorted { $0.addedAt > $1.addedAt }
        try expire()
    }
    private func save(_ record: ShelfRecord) throws {
        let destination = root.appendingPathComponent(record.folder.uuidString).appendingPathComponent(manifestName)
        try JSONEncoder().encode(record).write(to: destination, options: .atomic)
    }
    @discardableResult func add(_ source: URL) throws -> URL {
        guard source.isFileURL, valid(source.lastPathComponent) else { throw CocoaError(.fileReadInvalidFileName) }
        // Copy the target of a symbolic link so that the shelf owns an independent object.
        let actualSource = source.resolvingSymlinksInPath()
        let record = ShelfRecord(folder: UUID(), filename: source.lastPathComponent, addedAt: now())
        let directory = root.appendingPathComponent(record.folder.uuidString, isDirectory: true)
        // Do not copy an ancestor of our storage recursively into itself.
        let sourcePath = actualSource.standardizedFileURL.path
        let storagePath = root.resolvingSymlinksInPath().path
        guard storagePath != sourcePath, !storagePath.hasPrefix(sourcePath + "/") else { throw CocoaError(.fileWriteInvalidFileName) }
        try prepareRoot()
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try manager.copyItem(at: actualSource, to: url(for: record))
            try save(record)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
        records.insert(record, at: 0)
        return url(for: record)
    }
    func remove(_ file: URL) throws {
        guard let record = records.first(where: { url(for: $0).standardizedFileURL == file.standardizedFileURL }) else { return }
        let directory = root.appendingPathComponent(record.folder.uuidString, isDirectory: true)
        if manager.fileExists(atPath: directory.path) { try manager.removeItem(at: directory) }
        records.removeAll { $0.folder == record.folder }
    }
    func expire() throws {
        let cutoff = now().addingTimeInterval(-lifetime())
        for record in records where record.addedAt <= cutoff {
            try remove(url(for: record))
        }
        records.removeAll { !manager.fileExists(atPath: url(for: $0).path) }
    }
}

// The application accesses storage only through this serial worker. No disk work or
// synchronous waits run on the main queue; snapshots arrive there in commit order.
final class ShelfWorker {
    enum Operation {
        case restore, expire, add(URL), remove(URL)
    }
    struct Snapshot {
        let files: [URL]
        let error: Error?
    }
    private let queue = DispatchQueue(label: "NotchIsland.Shelf", qos: .userInitiated)
    private let store: ShelfStore
    init(root: URL? = nil, lifetime: @escaping () -> TimeInterval = {
        let hours = UserDefaults.standard.integer(forKey: "shelfHours")
        return TimeInterval([6, 12, 24].contains(hours) ? hours : 24) * 3600
    }) {
        if let root = root { store = ShelfStore(root: root, lifetime: lifetime) }
        else { store = ShelfStore(lifetime: lifetime) }
    }
    func run(_ operation: Operation, completion: @escaping (Snapshot) -> Void) {
        queue.async { [self] in
            var failure: Error?
            do {
                switch operation {
                case .restore: try store.restore()
                case .expire: try store.expire()
                case .add(let source): try store.add(source)
                case .remove(let file): try store.remove(file)
                }
            } catch { failure = error }
            let snapshot = Snapshot(files: store.files, error: failure)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }
}
