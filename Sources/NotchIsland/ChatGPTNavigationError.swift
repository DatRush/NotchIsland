import Foundation

enum ChatGPTNavigationError {
    static func message(for error: Error) -> String? {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else {
            return L("Не удалось загрузить страницу. Нажми обновление; если ошибка повторится, открой ChatGPT в браузере.", "Could not load the page. Reload, or open ChatGPT in your browser if the error persists.")
        }
        switch error.code {
        case NSURLErrorCancelled: return nil
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return L("Соединение с сетью потеряно. После восстановления нажми обновление.", "Network connection lost. Reload once it is restored.")
        case NSURLErrorTimedOut:
            return L("ChatGPT не ответил вовремя. Попробуй обновить страницу позже.", "ChatGPT did not respond in time. Try reloading later.")
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return L("Не удалось подключиться к ChatGPT. Проверь сеть и нажми обновление.", "Could not connect to ChatGPT. Check your network and reload.")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return L("Не удалось установить защищённое соединение. Проверь дату и сеть или открой ChatGPT в браузере.", "Could not establish a secure connection. Check your date and network, or open ChatGPT in a browser.")
        default:
            return L("Не удалось загрузить страницу. Нажми обновление; если ошибка повторится, открой ChatGPT в браузере.", "Could not load the page. Reload, or open ChatGPT in your browser if the error persists.")
        }
    }
}

/// Controls document navigation, not the website's subresource requests.
enum ChatGPTNavigationPolicy {
    enum Decision: Equatable { case allow, cancel, confirm(String) }
    static func decision(_ url: URL, mainFrame: Bool, approvedHosts: Set<String>) -> Decision {
        if url.absoluteString == "about:blank" { return .allow }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443 else { return .cancel }
        // Frames keep working for login/challenges. They cannot approve top-level hosts.
        guard mainFrame else { return .allow }
        let builtIn: Set<String> = ["chatgpt.com", "auth.openai.com", "auth0.openai.com"]
        if builtIn.contains(host) || approvedHosts.contains(host) { return .allow }
        return .confirm(host)
    }
    static func alert(for host: String) -> (String, String) {
        (L("Открыть сторонний сайт?", "Open an external website?"),
         L("Сайт: ", "Website: ") + host + "\n\n" +
         L("Можно открыть сайт в браузере или разрешить его внутри NotchIsland до перезапуска. Для продолжения входа может потребоваться открытие здесь. Сайт получит сетевые данные и сможет сохранять данные во встроенном браузере.",
           "Open this website in your browser, or allow it inside NotchIsland until restart. Continuing sign-in may require opening it here. The website will receive connection information and may store data in the embedded browser."))
    }
}
