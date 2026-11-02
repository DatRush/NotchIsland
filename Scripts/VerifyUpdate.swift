// Verify the published bytes against the public key pinned in the host app.
import CryptoKit
import Foundation

struct InvalidUpdate: Error {}
func require(_ condition: Bool) throws { if !condition { throw InvalidUpdate() } }
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 else { throw InvalidUpdate() }
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: args[0])), format: nil) as? [String: Any]
guard let encoded = info?["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: encoded),
      let version = info?["CFBundleShortVersionString"] as? String, let build = info?["CFBundleVersion"] as? String else { throw InvalidUpdate() }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let feed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let marker = Data("<!-- sparkle-signatures:\n".utf8)
guard let offset = feed.range(of: marker, options: .backwards)?.lowerBound,
      let trailer = String(data: feed[offset...], encoding: .utf8) else { throw InvalidUpdate() }
let lines = trailer.components(separatedBy: "\n")
guard lines.count == 5, lines[1].hasPrefix("edSignature: "),
      let signature = Data(base64Encoded: String(lines[1].dropFirst("edSignature: ".count))) else { throw InvalidUpdate() }
try require(lines[2] == "length: \(offset)" && lines[3] == "-->" && lines[4].isEmpty)
let content = feed.prefix(offset)
try require(key.isValidSignature(signature, for: content))
let xml = try XMLDocument(data: content)
guard let item = try xml.nodes(forXPath: "/rss/channel/item").first as? XMLElement,
      let enclosure = item.elements(forName: "enclosure").first,
      let sig = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue.flatMap({ Data(base64Encoded: $0) }) else { throw InvalidUpdate() }
let archive = URL(fileURLWithPath: args[2])
let data = try Data(contentsOf: archive, options: .mappedIfSafe)
try require(key.isValidSignature(sig, for: data))
try require(enclosure.attribute(forName: "length")?.stringValue == String(data.count))
try require(item.elements(forName: "sparkle:version").first?.stringValue == build)
try require(item.elements(forName: "sparkle:shortVersionString").first?.stringValue == version)
try require(enclosure.attribute(forName: "url")?.stringValue == "https://github.com/DatRush/NotchIsland/releases/download/v\(version)/\(archive.lastPathComponent)")
print("Verified feed and DMG with the app’s public key (version \(version), build \(build)).")
