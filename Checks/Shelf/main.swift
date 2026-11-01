import Foundation
let manager = FileManager.default
let temporary = manager.temporaryDirectory.appendingPathComponent("notch-shelf-check-" + UUID().uuidString)
try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: temporary) }
let source = temporary.appendingPathComponent("original.txt")
try Data("original payload".utf8).write(to: source)
let root = temporary.appendingPathComponent("storage")
var clock = Date()
var hours = 24.0
func makeStore() -> ShelfStore { ShelfStore(root: root, now: { clock }, lifetime: { hours * 3600 }) }
let first = makeStore()
try first.restore()
let copy = try first.add(source)
let copiedData = try Data(contentsOf: copy)
let sourceData = try Data(contentsOf: source)
precondition(copiedData == sourceData)
let second = makeStore()
try second.restore()
precondition(second.files == [copy])
clock = clock.addingTimeInterval(24 * 3600 - 1)
try second.expire(); precondition(second.files.count == 1)
clock = clock.addingTimeInterval(1)
try second.expire(); precondition(second.files.isEmpty)
precondition(manager.fileExists(atPath: source.path))
precondition(!manager.fileExists(atPath: copy.path))
hours = 12
let newCopy = try second.add(source)
clock = clock.addingTimeInterval(7 * 3600)
let third = makeStore(); try third.restore()
precondition(third.files == [newCopy])
try third.remove(source); precondition(third.files.count == 1)
try third.remove(newCopy); precondition(third.files.isEmpty)
let originalText = try String(contentsOf: source)
precondition(originalText == "original payload")
let legacy = root.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: legacy, withIntermediateDirectories: true)
try manager.copyItem(at: source, to: legacy.appendingPathComponent("legacy.txt"))
clock = Date()
let migrated = makeStore(); try migrated.restore()
precondition(migrated.files.count == 1)
precondition(manager.fileExists(atPath: legacy.appendingPathComponent(".shelf-entry.json").path))
let invalid = root.appendingPathComponent(UUID().uuidString)
try manager.createDirectory(at: invalid, withIntermediateDirectories: true)
try Data("broken".utf8).write(to: invalid.appendingPathComponent(".shelf-entry.json"))
try migrated.restore(); precondition(manager.fileExists(atPath: invalid.path))
let link = temporary.appendingPathComponent("link.txt")
try manager.createSymbolicLink(at: link, withDestinationURL: source)
let independent = try migrated.add(link)
let attributes = try independent.resourceValues(forKeys: [.isSymbolicLinkKey])
precondition(attributes.isSymbolicLink != true)
try migrated.remove(independent)
precondition(manager.fileExists(atPath: source.path))
do { try migrated.add(temporary); fatalError("Ancestor copy must fail") } catch {}
print("PASS: copy, restoration, 24h boundary, 12h retention, safe removal, legacy migration, damaged metadata, symlink copy, ancestor rejection")
let orderedRoot = temporary.appendingPathComponent("ordered")
let ordered = ShelfStore(root: orderedRoot, now: { clock })
try ordered.restore()
let older = try ordered.add(source)
clock = clock.addingTimeInterval(1)
let newer = try ordered.add(source)
precondition(ordered.files == [newer, older])
let reordered = ShelfStore(root: orderedRoot, now: { clock })
try reordered.restore()
precondition(reordered.files == [newer, older])
print("PASS: newest first before and after restart")

// Exercise the same asynchronous owner used by Model, with simultaneous callers.
let workerRoot = temporary.appendingPathComponent("worker")
let worker = ShelfWorker(root: workerRoot)
var callbacks = 0
var workerErrors = 0
var latest: [URL] = []
func receive(_ snapshot: ShelfWorker.Snapshot) {
    precondition(Thread.isMainThread)
    callbacks += 1
    if snapshot.error != nil { workerErrors += 1 }
    latest = snapshot.files
}
func pump(until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(30)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    precondition(condition(), "Worker completion timed out")
}
worker.run(.restore, completion: receive)
pump { callbacks == 1 }
DispatchQueue.concurrentPerform(iterations: 60) { i in
    switch i % 3 {
    case 0: worker.run(.add(source), completion: receive)
    case 1: worker.run(.expire, completion: receive)
    default: worker.run(.remove(source), completion: receive) // Never delete originals.
    }
}
pump { callbacks == 61 }
precondition(workerErrors == 0 && latest.count == 20)
let owned = latest
DispatchQueue.concurrentPerform(iterations: owned.count) { i in
    worker.run(.remove(owned[i]), completion: receive)
    worker.run(.expire, completion: receive)
}
pump { callbacks == 101 }
precondition(latest.isEmpty && manager.fileExists(atPath: source.path))
worker.run(.add(source), completion: receive)
worker.run(.add(temporary.appendingPathComponent("missing")), completion: receive)
worker.run(.add(source), completion: receive)
pump { callbacks == 104 }
precondition(workerErrors == 1 && latest.count == 2)
let persisted = ShelfStore(root: workerRoot)
try persisted.restore()
precondition(persisted.files == latest)
print("PASS: concurrent add/remove/expire, ordered main-thread snapshots, partial failure, newest first, originals preserved")

// Many small files are intentionally slower than an APFS clone of one large file.
let directory = temporary.appendingPathComponent("large-directory")
try manager.createDirectory(at: directory, withIntermediateDirectories: true)
let payload = Data(repeating: 0x63, count: 32 * 1024)
for i in 0..<3000 { try payload.write(to: directory.appendingPathComponent("item-\(i).bin")) }
var beats = 0
var finishedCopy = false
var lastBeat = Date()
var largestGap = 0.0
let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
    let current = Date()
    largestGap = max(largestGap, current.timeIntervalSince(lastBeat))
    lastBeat = current
    beats += 1
}
let started = Date()
worker.run(.add(directory)) { snapshot in
    receive(snapshot)
    finishedCopy = true
}
pump { finishedCopy }
heartbeat.invalidate()
precondition(workerErrors == 1 && beats > 0, "Main run loop must remain responsive while copying")
let directoryCopy = latest[0]
let copiedCount = try manager.contentsOfDirectory(atPath: directoryCopy.path).count
precondition(copiedCount == 3000)
for i in [0, 1499, 2999] {
    let contents = try Data(contentsOf: directoryCopy.appendingPathComponent("item-\(i).bin"))
    precondition(contents == payload)
}
worker.run(.remove(directoryCopy), completion: receive)
pump { callbacks == 106 }
let originalCount = try manager.contentsOfDirectory(atPath: directory.path).count
precondition(originalCount == 3000)
print("PASS: 3000-file / 94 MiB directory, main run-loop heartbeats: \(beats), largest heartbeat gap: \(largestGap)s, elapsed: \(Date().timeIntervalSince(started))s, original intact after removal")

let expiring = ShelfWorker(root: temporary.appendingPathComponent("expiring-worker"), lifetime: { 0 })
var expiryCallbacks = 0
var expiryFiles: [URL] = []
DispatchQueue.concurrentPerform(iterations: 20) { _ in
    expiring.run(.add(source)) { snapshot in
        precondition(snapshot.error == nil)
        expiryCallbacks += 1
    }
    expiring.run(.expire) { snapshot in
        precondition(snapshot.error == nil)
        expiryFiles = snapshot.files
        expiryCallbacks += 1
    }
}
pump { expiryCallbacks == 40 }
precondition(expiryFiles.isEmpty)
let survivingOriginal = try Data(contentsOf: source)
precondition(survivingOriginal == sourceData)
print("PASS: concurrent adds and actual expiry remove only owned copies")

// Exercise the production default lifetime, including migration of the old 48h choice.
let savedRetention = UserDefaults.standard.object(forKey: "shelfHours")
defer {
    if let savedRetention { UserDefaults.standard.set(savedRetention, forKey: "shelfHours") }
    else { UserDefaults.standard.removeObject(forKey: "shelfHours") }
}
for setting in [6, 12, 24, 48, 0] {
    UserDefaults.standard.set(setting, forKey: "shelfHours")
    let expected = [6, 12, 24].contains(setting) ? setting : 24
    var testTime = Date()
    let store = ShelfStore(root: temporary.appendingPathComponent("duration-\(setting)"), now: { testTime })
    try store.restore()
    let copied = try store.add(source)
    testTime = testTime.addingTimeInterval(Double(expected * 3600 - 1))
    try store.expire()
    precondition(store.files == [copied])
    testTime = testTime.addingTimeInterval(1)
    try store.expire()
    precondition(store.files.isEmpty && manager.fileExists(atPath: source.path))
}
print("PASS: default 6/12/24h expiry boundaries, 48h migration, invalid preference fallback")

let privateRoot = temporary.appendingPathComponent("private-storage")
try manager.createDirectory(at: privateRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
let privateStore = ShelfStore(root: privateRoot)
try privateStore.restore()
let protectedMode = try manager.attributesOfItem(atPath: privateRoot.path)[.posixPermissions] as! NSNumber
precondition(protectedMode.intValue == 0o700)
let privateCopy = try privateStore.add(source)
let entryMode = try manager.attributesOfItem(atPath: privateCopy.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
precondition(entryMode.intValue == 0o700)
let linkedRoot = temporary.appendingPathComponent("linked-root")
try manager.createSymbolicLink(at: linkedRoot, withDestinationURL: privateRoot)
do { try ShelfStore(root: linkedRoot).restore(); fatalError("Symbolic root accepted") } catch {}
print("PASS: existing shelf root hardened, private entry directory, symbolic root rejected")
