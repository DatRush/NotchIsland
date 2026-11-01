import SwiftUI

struct HomeReminderView: View {
    @ObservedObject var store: AppleReminderStore
    let open: (AppleReminder?) -> Void
    private var next: AppleReminder? { store.ordered.first { $0.due != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("Ближайшее напоминание", "Next reminder")).font(.system(size: 11)).foregroundColor(.gray)
            Button { open(next) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next?.text ?? emptyTitle)
                            .font(.system(size: 12)).lineLimit(1)
                        if let reminder = next, let due = reminder.due {
                            Text(dateText(due, hasTime: reminder.hasTime))
                                .font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundColor(.gray)
                }.padding(.horizontal, 11).frame(height: 42)
                    .background(Color.white.opacity(0.09)).cornerRadius(10)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.onAppear { store.refresh() }
    }
    private var emptyTitle: String {
        if !store.authorized { return L("Подключить Apple Reminders", "Connect Apple Reminders") }
        if store.listID.isEmpty { return L("Выбрать список напоминаний", "Choose a reminder list") }
        if store.busy { return L("Загружаем…", "Loading…") }
        if !store.message.isEmpty { return L("Не удалось обновить · Открыть напоминания", "Could not refresh · Open reminders") }
        return L("Нет напоминаний с датой", "No dated reminders")
    }
    private func dateText(_ date: Date, hasTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateStyle = .short
        formatter.timeStyle = hasTime ? .short : .none
        formatter.doesRelativeDateFormatting = true
        let overdue = hasTime ? date < Date() : date < Calendar.current.startOfDay(for: Date())
        return (overdue ? L("Просрочено · ", "Overdue · ") : "") + formatter.string(from: date)
    }
}
