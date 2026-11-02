import AppKit
import Sparkle

let app = NSApplication.shared
guard CommandLine.arguments.count == 2,
      let bundle = Bundle(path: CommandLine.arguments[1]) else { exit(2) }
let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
do {
    try updater.start()
    print("Sparkle startup passed for packaged app")
} catch {
    let failure = error as NSError
    fputs("\(failure.domain) \(failure.code): \(failure.localizedDescription)\n", stderr)
    exit(1)
}
