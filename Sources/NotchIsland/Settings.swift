import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var folder: String { didSet { UserDefaults.standard.set(folder, forKey: "screenshotFolder") } }
    @Published var retention: Int { didSet { UserDefaults.standard.set(retention, forKey: "shelfHours") } }
    @Published var excluded: [String] { didSet { UserDefaults.standard.set(excluded, forKey: "excludedApps") } }
    @Published var clipboardExcluded: [String] { didSet { UserDefaults.standard.set(clipboardExcluded, forKey: ClipboardPrivacy.excludedKey) } }
    @Published var loginEnabled = false
    @Published var notice = ""
    init() {
        folder = UserDefaults.standard.string(forKey: "screenshotFolder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/NotchIsland").path
        let savedHours = UserDefaults.standard.integer(forKey: "shelfHours")
        retention = [6, 12, 24].contains(savedHours) ? savedHours : 24
        excluded = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
        clipboardExcluded = UserDefaults.standard.stringArray(forKey: ClipboardPrivacy.excludedKey) ?? []
        UserDefaults.standard.set(retention, forKey: "shelfHours")
        refreshLogin()
    }
    func refreshLogin() { loginEnabled = SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            notice = SMAppService.mainApp.status == .requiresApproval ? L("Разреши запуск в Системных настройках → Основные → Объекты входа.", "Allow startup in System Settings → General → Login Items.") : ""
        } catch { notice = L("Не удалось изменить автозапуск: \(error.localizedDescription)", "Could not change login startup: \(error.localizedDescription)") }
        refreshLogin()
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folder)
        panel.prompt = L("Выбрать", "Choose")
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
    func addExclusion(forClipboard: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Добавить", "Add")
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            if forClipboard {
                if !clipboardExcluded.contains(id) { clipboardExcluded.append(id) }
            } else if !excluded.contains(id) { excluded.append(id) }
        }
    }
    var blocksCurrentApp: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return excluded.contains(id)
    }
}

struct PreferencesView: View {
    @AppStorage(AppLanguage.key) private var language = "ru"
    @AppStorage("musicCaptureArtwork") private var captureMusicArtwork = true
    @AppStorage(RemoteArtworkPolicy.preferenceKey) private var remoteMusicArtwork = false
    @ObservedObject var chatGPT = ChatGPTSession.shared
    @ObservedObject var preferences = Preferences.shared
    var body: some View {
        Form {
            Section(L("Язык", "Language")) {
                Picker(L("Язык интерфейса", "Interface language"), selection: $language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                Text(L("Язык ChatGPT задаётся в самом ChatGPT.", "ChatGPT language is managed in ChatGPT."))
                    .font(.caption).foregroundColor(.secondary)
            }
            WeatherSettings()
            Section(L("Музыка", "Music")) {
                Toggle(L("Обложка Яндекса из окна плеера", "Capture Yandex artwork from its window"), isOn: $captureMusicArtwork)
                Toggle(L("Загружать обложки YouTube из интернета", "Download YouTube artwork from the internet"), isOn: $remoteMusicArtwork)
                    .onChange(of: remoteMusicArtwork) { _ in MusicPlayback.shared.remoteArtworkPreferenceChanged() }
                Text(L("Выключено по умолчанию. При включении Google получает IP-адрес и идентификатор видео, в том числе когда вкладка музыки закрыта. Выключение останавливает текущую загрузку.", "Off by default. When enabled, Google receives your IP address and the video identifier, including while the Music tab is closed. Turning this off stops the current download."))
                    .font(.caption).foregroundColor(.secondary)
                Button(L("Подключить управление плеерами…", "Connect player controls…")) { MusicPlayback.shared.connect() }
                Text(L("Apple Music — Automation; Яндекс Музыка и YouTube — Универсальный доступ. Во время воспроизведения слева показывается обложка, справа — индикатор активного таймера или музыкальные полосы.", "Apple Music uses Automation; Yandex Music and YouTube use Accessibility. During playback, artwork appears on the left and the active timer indicator or music bars on the right."))
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(L("Скриншоты", "Screenshots")) {
                HStack {
                    Text(preferences.folder).lineLimit(2).truncationMode(.middle)
                    Spacer()
                    Button(L("Выбрать…", "Choose…")) { preferences.chooseFolder() }
                }
                Text(L("Снимки сохраняются сюда и копируются в буфер как изображение.", "Screenshots are saved here and copied to the clipboard as images.")).font(.caption).foregroundColor(.secondary)
            }
            Section("ChatGPT") {
                Button(L("Очистить локальные данные ChatGPT…", "Clear local ChatGPT data…"), action: chatGPT.confirmReset)
                    .disabled(chatGPT.isResetting)
                Text(L("Сброс входа, cookies и кэша встроенного браузера. Переписка в аккаунте и сохранённые снимки остаются.", "Reset embedded-browser sign-ins, cookies and cache. Account conversations and saved screenshots remain."))
                    .font(.caption).foregroundColor(.secondary)
                if chatGPT.isResetting { Text(L("Очистка данных…", "Clearing data…")).font(.caption) }
                if let message = chatGPT.resetMessage { Text(message).font(.caption).foregroundColor(.secondary) }
            }
            Section(L("Полка", "Shelf")) {
                Picker(L("Удалять временные копии", "Delete temporary copies"), selection: $preferences.retention) {
                    Text(L("Через 6 часов", "After 6 hours")).tag(6)
                    Text(L("Через 12 часов", "After 12 hours")).tag(12)
                    Text(L("Через 24 часа", "After 24 hours")).tag(24)
                }
                Text(L("Срок отсчитывается от добавления файла. Очистка — при открытии, после сна и раз в минуту. Оригиналы остаются на месте.", "Retention starts when a file is added. Cleanup runs on opening, after wake and every minute. Original files remain untouched.")).font(.caption).foregroundColor(.secondary)
            }
            Section(L("Конфиденциальность буфера", "Clipboard privacy")) {
                HStack {
                    Text(L("Не сохранять из приложений", "Do not capture from these apps"))
                    Spacer()
                    Button(L("Добавить…", "Add…")) { preferences.addExclusion(forClipboard: true) }
                }
                ForEach(preferences.clipboardExcluded, id: \.self) { id in
                    HStack {
                        Text(appName(id)).lineLimit(1)
                        Spacer()
                        Button { preferences.clipboardExcluded.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(L("Убрать исключение буфера", "Remove clipboard exclusion"))
                    }
                }
                if preferences.clipboardExcluded.isEmpty { Text(L("Исключений нет", "No exclusions")).foregroundColor(.secondary) }
                Text(L("Применяется к новым копированиям, пока выбранное приложение активно. Старые записи можно удалить в истории.", "Applies to new copies while the selected app is active. Existing entries can be removed from history."))
                    .font(.caption).foregroundColor(.secondary)
                Text(L("Помеченные приложением скрытые данные пропускаются. Для остальных чувствительных данных включай паузу записи.", "Data marked as concealed by an app is skipped. Pause recording for other sensitive content."))
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(L("Поведение", "Behavior")) {
                Toggle(L("Запускать при входе", "Launch at login"), isOn: Binding(get: { preferences.loginEnabled }, set: preferences.setLogin))
                if !preferences.notice.isEmpty { Text(preferences.notice).font(.caption).foregroundColor(.secondary) }
                HStack {
                    Text(L("Не открывать поверх приложений", "Do not open over these apps"))
                    Spacer()
                    Button(L("Добавить…", "Add…")) { preferences.addExclusion() }
                }
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(preferences.excluded, id: \.self) { id in
                            HStack {
                                Text(appName(id)).lineLimit(1)
                                Spacer()
                                Button { preferences.excluded.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).help(L("Убрать исключение", "Remove exclusion"))
                            }
                        }
                        if preferences.excluded.isEmpty { Text(L("Исключений нет", "No exclusions")).foregroundColor(.secondary) }
                    }
                }.frame(height: 70)
            }
        }.onChange(of: language) { _ in
            NotificationCenter.default.post(name: AppLanguage.changed, object: nil)
        }.formStyle(.grouped).frame(width: 500, height: 560)
            .onAppear { preferences.refreshLogin() }
    }
    private func appName(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
    }
}

final class DraftTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = textContainerOrigin
        let point = NSPoint(x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y)
        (L("Спросить ChatGPT…", "Ask ChatGPT…") as NSString).draw(at: point, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
}

struct DraftEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let editor = DraftTextView(frame: NSRect(x: 0, y: 0, width: 329, height: 70))
        editor.minSize = NSSize(width: 0, height: 70)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 13); editor.textColor = .white
        editor.insertionPointColor = .controlAccentColor
        editor.textContainerInset = NSSize(width: 0, height: 8)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(L("Вопрос ChatGPT", "ChatGPT question"))
        scroll.documentView = editor
        editor.string = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let editor = scroll.documentView as? NSTextView, editor.string != text { editor.string = text; editor.needsDisplay = true }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditor
        init(_ parent: DraftEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}
