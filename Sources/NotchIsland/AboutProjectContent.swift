import Foundation

struct AboutProjectContent {
    static let author = ""
    static var story: String { L("""
    NotchIsland это бесплатная утилита для MacBook, созданная с помощью Codex от OpenAI.

    Я собрал в ней инструменты, которых мне самому не хватало в повседневной работе.
    Буду рад вашим идеям, пожеланиям и участию в разработке.
    """, """
    NotchIsland is a free MacBook utility created with the help of Codex by OpenAI.

    I brought together the tools I felt were missing from my daily workflow.
    Ideas, suggestions and contributions are always welcome.
    """) }
    static var features: String { L("""
    • История буфера обмена и быстрый доступ к последнему скопированному.
    • Полка для временных копий файлов и перенос между приложениями.
    • Скриншоты выбранной области и работа с вашим аккаунтом ChatGPT.
    • Таймер, напоминания Apple.
    • Обложка и управление активным плеером Apple Music, Яндекс Музыки или YouTube. Для видео YouTube приложение проверяет категорию и теги на публичной странице ролика.
    • С разрешением на запись системного звука полосы реагируют на музыку.
    • Перестановка вкладок под себя.
    """, """
    • Clipboard history and quick access to your last copied item.
    • A shelf for temporary file copies and transfers between apps.
    • Area screenshots and access to your ChatGPT account.
    • Timer and Apple Reminders.
    • Artwork and playback controls for Apple Music, Yandex Music and YouTube. For YouTube videos the app checks the category and tags on the public video page.
    • With system audio capture permission the bars react to the music.
    • Reorder tabs to suit your workflow.
    """) }
    static var supportDetails: String { L("Проект распространяется бесплатно. Если он оказался вам полезен, буду благодарен за любую финансовую поддержку на Boosty.", "The project is free. If you find it useful, I would be grateful for any financial support on Boosty.") }
    static let repositoryURL = URL(string: "https://github.com/DatRush/NotchIsland")!
    static let supportURL: URL? = URL(string: "https://boosty.to/taykwn/donate")
}
