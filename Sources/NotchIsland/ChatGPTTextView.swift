import AppKit
import SwiftUI

struct ChatGPTTextTools: View {
    @ObservedObject var session: ChatGPTSession
    var body: some View {
        Menu {
            Button(L("Последний ответ", "Last response")) { session.copyResponse(selectionOnly: false) }
            Button(L("Выделенный фрагмент", "Selected text")) { session.copyResponse(selectionOnly: true) }
        } label: { Image(systemName: "doc.on.doc") }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L("Копировать ответ", "Copy response")).accessibilityLabel(L("Копировать ответ", "Copy response"))
    }
}
