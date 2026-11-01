import SwiftUI

struct LocalizedRoot<Content: View>: View {
    @AppStorage(AppLanguage.key) private var language = "ru"
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().environment(\.locale, Locale(identifier: language == "en" ? "en_US" : "ru_RU"))
    }
}
