import SwiftUI

struct AboutProjectView: View {
    private struct PolicyDocument: Identifiable {
        let id: URL
        let text: String
    }

    @State private var privacyDocument: PolicyDocument?
    @State private var missingDocument = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(nsImage: BrandIcon.image(size: 64, template: true, background: false))
                        .resizable().renderingMode(.template).frame(width: 64, height: 64).padding(.bottom, 4)
                    Text("NotchIsland").font(.system(size: 28, weight: .semibold))
                    if !AboutProjectContent.author.isEmpty {
                        Text(AboutProjectContent.author).foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("О проекте", "About")).font(.headline)
                    Text(AboutProjectContent.story.isEmpty ? L("Здесь скоро появится история проекта от автора.", "The author's project story will appear here soon.") : AboutProjectContent.story)
                        .font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                    Link(destination: AboutProjectContent.repositoryURL) {
                        actionLabel(L("Репозиторий на GitHub", "GitHub repository"), icon: "arrow.up.right")
                    }.buttonStyle(.plain)
                }
                Divider()
                infoSection(L("Что умеет приложение", "Features"), text: AboutProjectContent.features)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Поддержать проект", "Support the project")).font(.headline)
                    if AboutProjectContent.supportDetails.isEmpty && AboutProjectContent.supportURL == nil {
                        Text(L("Информация о поддержке появится здесь позже.", "Support information will appear here later."))
                            .font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    if !AboutProjectContent.supportDetails.isEmpty {
                        Text(AboutProjectContent.supportDetails).font(.system(size: 13))
                            .lineSpacing(4).textSelection(.enabled)
                    }
                    if let url = AboutProjectContent.supportURL {
                        Link(destination: url) {
                            actionLabel(L("Поддержать на Boosty", "Support on Boosty"), icon: "arrow.up.right")
                        }.buttonStyle(.plain)
                    }
                }
                Button {
                    guard let url = Bundle.main.url(forResource: L("PRIVACY", "PRIVACY.en"), withExtension: "md"),
                          let document = try? String(contentsOf: url, encoding: .utf8),
                          !document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        missingDocument = true
                        return
                    }
                    privacyDocument = PolicyDocument(id: url, text: document)
                } label: {
                    actionLabel(L("Политика конфиденциальности", "Privacy policy"), icon: "doc.text")
                }
                .buttonStyle(.plain)
                .alert(L("Файл политики отсутствует в сборке.", "The privacy policy is missing from this build."),
                       isPresented: $missingDocument) {
                    Button("OK") {}
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }.background(Color(nsColor: .windowBackgroundColor)).foregroundColor(.primary)
        .sheet(item: $privacyDocument) { policy in
            PrivacyReader(document: policy.text)
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func infoSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
        }
    }
}

// Keep the installed policy readable offline, including on Macs without a Markdown previewer.
struct PrivacyReader: View {
    let document: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(document.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                        if block.hasPrefix("#") {
                            Text(verbatim: String(block.drop(while: { $0 == "#" || $0 == " " })))
                                .font(block.hasPrefix("# ") ? .title : .headline)
                        } else if block.hasPrefix("|") {
                            ForEach(Array(block.split(separator: "\n").enumerated()), id: \.offset) { _, row in
                                let cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                                if let first = cells.first, !first.hasPrefix("---") {
                                    Text(inline(cells.joined(separator: " — ")))
                                }
                            }
                        } else {
                            Text(inline(block.replacingOccurrences(of: "[English](PRIVACY.en.md)", with: "")
                                .replacingOccurrences(of: "[Русский](PRIVACY.md)", with: "")))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding()
            }
            Button(L("Закрыть", "Close")) { dismiss() }.keyboardShortcut(.cancelAction).padding()
        }.frame(minWidth: 500, idealWidth: 600, minHeight: 360, idealHeight: 520)
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
