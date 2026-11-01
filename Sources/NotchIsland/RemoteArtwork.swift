import Foundation
import ImageIO

/// The only remote artwork endpoint supported by the browser-player adapter.
/// It must not become a general-purpose URL loader for accessibility-provided URLs.
enum RemoteArtworkPolicy {
    static let preferenceKey = "musicRemoteArtwork"
    static let maximumBytes = 4_000_000
    static func allows(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "i.ytimg.com",
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              parts.query == nil, parts.fragment == nil else { return false }
        return parts.percentEncodedPath.range(of: #"^/vi/[A-Za-z0-9_-]{11}/hqdefault\.jpg$"#,
                                              options: .regularExpression) != nil
    }
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        return config
    }
    static func accepts(_ response: HTTPURLResponse) -> Bool {
        guard let url = response.url, allows(url), response.statusCode == 200,
              ["image/jpeg", "image/png"].contains(response.mimeType?.lowercased() ?? "") else { return false }
        return response.expectedContentLength <= Int64(maximumBytes)
    }
    static func decodable(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              ["public.jpeg", "public.png"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2048, height <= 2048 else { return false }
        return true
    }
}

/// All state and callbacks are confined to the main queue. Each request owns a
/// short-lived session; finishing or cancelling breaks the session/delegate cycle.
final class RemoteArtworkRequest: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var bytes = Data()
    private var acceptedResponse = false
    private var finished = false
    private var completion: ((Data?) -> Void)?

    @discardableResult
    static func start(_ url: URL, protocolClasses: [AnyClass]? = nil,
                      completion: @escaping (Data?) -> Void) -> RemoteArtworkRequest? {
        precondition(Thread.isMainThread)
        guard RemoteArtworkPolicy.allows(url) else { completion(nil); return nil }
        let request = RemoteArtworkRequest()
        request.completion = completion
        let configuration = RemoteArtworkPolicy.configuration()
        // Tests can inject a transport without using the network or shared stores.
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        let session = URLSession(configuration: configuration, delegate: request, delegateQueue: .main)
        request.session = session
        var message = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        message.httpShouldHandleCookies = false
        message.setValue("image/jpeg, image/png", forHTTPHeaderField: "Accept")
        request.task = session.dataTask(with: message)
        request.task?.resume()
        return request
    }
    func cancel() {
        precondition(Thread.isMainThread)
        finish(nil)
    }
    private func finish(_ data: Data?) {
        guard !finished else { return }
        finished = true
        let callback = completion
        completion = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        bytes.removeAll()
        callback?(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Even a redirect to the same host is unnecessary for this fixed endpoint.
        completionHandler(nil)
        finish(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished, let response = response as? HTTPURLResponse,
              RemoteArtworkPolicy.accepts(response) else {
            completionHandler(.cancel); finish(nil); return
        }
        acceptedResponse = true
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard acceptedResponse, data.count <= RemoteArtworkPolicy.maximumBytes - bytes.count else {
            finish(nil); return
        }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        let result = error == nil && acceptedResponse && RemoteArtworkPolicy.decodable(bytes) ? bytes : nil
        finish(result)
    }
}
