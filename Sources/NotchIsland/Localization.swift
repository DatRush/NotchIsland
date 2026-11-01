import Foundation

enum AppLanguage {
    static let key = "interfaceLanguage"
    static var english: Bool { UserDefaults.standard.string(forKey: key) == "en" }
    static var locale: Locale { Locale(identifier: english ? "en_US" : "ru_RU") }
    static let changed = Notification.Name("NotchIslandLanguageChanged")
}

// Keep both translations beside each app-owned string. Never translate user content.
func L(_ russian: String, _ english: String) -> String {
    AppLanguage.english ? english : russian
}
