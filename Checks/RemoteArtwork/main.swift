import AppKit

var count = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    guard value() else { fatalError(label) }; count += 1
    print("PASS: \(label)")
}
func wait(_ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    check(predicate(), "asynchronous operation completed")
}
let allowed = URL(string: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg")!
check(RemoteArtworkPolicy.allows(allowed), "fixed artwork endpoint allowed")
for raw in [
    "http://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg",
    "https://i.ytimg.com.evil.invalid/vi/abcdefghijk/hqdefault.jpg",
    "https://evil.invalid/vi/abcdefghijk/hqdefault.jpg",
    "https://user:pass@i.ytimg.com/vi/abcdefghijk/hqdefault.jpg",
    "https://i.ytimg.com:444/vi/abcdefghijk/hqdefault.jpg",
    "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg?tracking=x",
    "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg#fragment",
    "https://i.ytimg.com/vi/short/hqdefault.jpg",
    "https://i.ytimg.com/vi/abcdefghijk/../hqdefault.jpg",
    "https://i.ytimg.com/vi/%61bcdefghijk/hqdefault.jpg",
    "https://i.ytimg.com/vi/abcdefghijk/other.jpg",
    "file:///private/tmp/example.jpg"
] { check(!RemoteArtworkPolicy.allows(URL(string: raw)!), "reject non-allowlisted URL") }
let config = RemoteArtworkPolicy.configuration()
check(config.httpCookieStorage == nil && !config.httpShouldSetCookies, "cookies disabled")
check(config.urlCache == nil && config.requestCachePolicy == .reloadIgnoringLocalCacheData, "no response cache")
check(config.urlCredentialStorage == nil, "credential storage disabled")
check(config.timeoutIntervalForResource == 20 && config.timeoutIntervalForRequest == 15, "bounded request and resource lifetime")

func png(width: Int = 4) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 3,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return bitmap.representation(using: .png, properties: [:])!
}
let payload = png()
check(RemoteArtworkPolicy.decodable(payload), "valid small image accepted")
check(!RemoteArtworkPolicy.decodable(png(width: 2049)), "excessive image dimensions rejected")
check(!RemoteArtworkPolicy.decodable(Data("not an image".utf8)), "non-image body rejected")
let tiff = NSBitmapImageRep(data: payload)!.representation(using: .tiff, properties: [:])!
check(!RemoteArtworkPolicy.decodable(tiff), "disguised unsupported image format rejected")

final class FixtureTransport: URLProtocol {
    static var handler: ((FixtureTransport) -> Void)?
    static var requests: [URLRequest] = []
    static var stopped = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.async {
            Self.requests.append(self.request)
            Self.handler?(self)
        }
    }
    override func stopLoading() { DispatchQueue.main.async { Self.stopped += 1 } }
    func respond(status: Int = 200, mime: String = "image/png", length: Int? = nil, chunks: [Data]) {
        var headers = ["Content-Type": mime, "Set-Cookie": "fixture=ignore; Secure", "Cache-Control": "max-age=3600"]
        if let length { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }
}
func run(_ handler: @escaping (FixtureTransport) -> Void) -> Data? {
    FixtureTransport.handler = handler
    var done = false
    var output: Data?
    var completions = 0
    let request = RemoteArtworkRequest.start(allowed, protocolClasses: [FixtureTransport.self]) {
        output = $0; completions += 1; done = true
    }
    wait { done }
    request?.cancel()
    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    check(completions == 1, "completion delivered once, including cancellation")
    return output
}
check(run { $0.respond(length: payload.count, chunks: [payload]) } == payload, "bounded image downloads through actual URLSession delegate")
check(FixtureTransport.requests.last?.httpShouldHandleCookies == false, "request refuses cookies")
check(FixtureTransport.requests.last?.value(forHTTPHeaderField: "Cookie") == nil, "no cookie header sent")
check(run { $0.respond(status: 403, chunks: [payload]) } == nil, "HTTP error rejected")
check(run { $0.respond(mime: "text/html", chunks: [payload]) } == nil, "HTML response rejected")
check(run { $0.respond(length: RemoteArtworkPolicy.maximumBytes + 1, chunks: []) } == nil, "oversize Content-Length rejected before body")
let chunk = Data(repeating: 0, count: 1_000_000)
check(run { $0.respond(chunks: [chunk, chunk, chunk, chunk, Data([0])]) } == nil, "unknown-length response rejected when streaming exceeds cap")
check(run { $0.respond(chunks: [Data("invalid".utf8)]) } == nil, "undecodable payload rejected after transfer")
check(run { $0.respond(chunks: [png(width: 2049)]) } == nil, "oversize pixels rejected before image display")

FixtureTransport.handler = { _ in } // Hold an in-flight request without response.
var cancelledCount = 0
let cancelled = RemoteArtworkRequest.start(allowed, protocolClasses: [FixtureTransport.self]) { data in
    check(data == nil, "cancelled request has no payload"); cancelledCount += 1
}
cancelled?.cancel(); cancelled?.cancel()
wait { cancelledCount == 1 }
check(cancelledCount == 1, "repeated cancellation is harmless")

for destination in [allowed, URL(string: "https://other.invalid/image")!] {
    var done = false
    let request = RemoteArtworkRequest.start(allowed, protocolClasses: [FixtureTransport.self]) { data in
        check(data == nil, "redirect never returns artwork"); done = true
    }!
    let session = URLSession(configuration: .ephemeral)
    let task = session.dataTask(with: allowed) // Never resumed.
    let redirect = HTTPURLResponse(url: allowed, statusCode: 302, httpVersion: nil, headerFields: ["Location": destination.absoluteString])!
    var refused = false
    request.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                       newRequest: URLRequest(url: destination)) { refused = $0 == nil }
    check(refused && done, "same-host and cross-host redirects refused")
    session.invalidateAndCancel()
}
let previousRequests = FixtureTransport.requests.count
var invalidCompleted = false
let invalid = RemoteArtworkRequest.start(URL(string: "https://example.invalid/a")!, protocolClasses: [FixtureTransport.self]) { data in
    invalidCompleted = data == nil
}
check(invalid == nil && invalidCompleted && FixtureTransport.requests.count == previousRequests, "invalid URL never starts a request")
print("Remote artwork: \(count) checks passed; synthetic transport only, no real network")
