import Foundation
let defaults = UserDefaults.standard
let saved = defaults.object(forKey: AppLanguage.key)
defer {
    if let saved { defaults.set(saved, forKey: AppLanguage.key) }
    else { defaults.removeObject(forKey: AppLanguage.key) }
}
for code in ["ru", "en", "unknown"] {
    defaults.set(code, forKey: AppLanguage.key)
    precondition(L("Да", "Yes") == (code == "en" ? "Yes" : "Да"))
    precondition(AppLanguage.locale.identifier == (code == "en" ? "en_US" : "ru_RU"))
    precondition(AboutProjectContent.story.contains(code == "en" ? "free MacBook" : "бесплатная"))
    precondition(AboutProjectContent.features.contains(code == "en" ? "Clipboard" : "История"))
    precondition(AboutProjectContent.supportURL?.absoluteString == "https://boosty.to/taykwn/donate")
}
print("PASS: live language selection, fallback, locale, About sections, unchanged support URL")
