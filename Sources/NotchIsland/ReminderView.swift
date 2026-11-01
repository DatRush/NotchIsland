import AppKit
import SwiftUI

struct RemindersView: View {
    @ObservedObject var store: AppleReminderStore
    @State private var checking: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleting: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if store.composing || store.selected != nil {
                    Button { store.composing = false; store.selectedID = nil } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(L("К списку напоминаний", "Back to reminders"))
                }
                Text(L("Напоминания", "Reminders")).font(.system(size: 14, weight: .semibold))
                Spacer()
                if !store.composing && !store.storageUnavailable {
                    Button { store.newReminder() } label: { Image(systemName: "plus") }
                        .help(L("Новое напоминание", "New reminder")).accessibilityLabel(L("Новое напоминание", "New reminder"))
                }
            }.buttonStyle(.plain).disabled(store.busy)
            if !store.authorized {
                Text(L("Задачи и уведомления Apple Reminders, синхронизация через выбранный аккаунт.", "Apple Reminders tasks and alerts, synced through your selected account.")).font(.system(size: 11)).foregroundColor(.gray)
                Button(L("Подключить Apple Reminders", "Connect Apple Reminders")) { store.connect() }.disabled(store.busy)
            } else if store.choosingList {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(L("Создать список NotchIsland в iCloud", "Create NotchIsland list in iCloud")) { store.createList() }
                        ForEach(store.lists) { list in
                            Button(list.title + " · " + list.account) { store.selectList(list.id) }
                        }
                        if !store.storageUnavailable {
                            Divider()
                            Button(L("Перенести локальные в выбранный список", "Import local reminders into this list")) { store.importLegacy() }
                            Button(L("Назад", "Back")) { store.choosingList = false }
                        }
                    }.font(.system(size: 11)).buttonStyle(.plain).disabled(store.busy)
                }
            } else if store.composing { editor }
            else if let reminder = store.selected { detail(reminder) }
            else { list }
            if let id = deleting {
                HStack {
                    Text(L("Удалить из Apple на всех устройствах?", "Delete from Apple on all devices?")).font(.system(size: 10))
                    Button(L("Удалить", "Delete")) { store.remove(id); deleting = nil }
                    Button(L("Отмена", "Cancel")) { deleting = nil }
                }.font(.system(size: 10)).buttonStyle(.plain)
            }
            if !store.message.isEmpty {
                ScrollView { Text(store.message).font(.system(size: 10)).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 24)
            }
        }.padding(.top, 4)
            .onAppear { store.refresh() }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $store.draft).font(.system(size: 12))
                .scrollContentBackground(.hidden).padding(5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .frame(height: 46).accessibilityLabel(L("Текст или ссылка для напоминания", "Reminder text or link"))
            HStack(spacing: 7) {
                ForEach([-1, 300, 600, 1800, 3600, 0], id: \.self) { seconds in
                    Button(seconds == -1 ? L("Без даты", "No date") : seconds == 0 ? L("Дата", "Date") : seconds == 3600 ? L("1 ч", "1 hr") : L("\(seconds / 60) м", "\(seconds / 60) min")) { store.interval = seconds }
                        .padding(.horizontal, 6).padding(.vertical, 5)
                        .background(Color.white.opacity(store.interval == seconds ? 0.22 : 0.07), in: Capsule())
                }
            }.font(.system(size: 11)).buttonStyle(.plain)
            HStack(spacing: 8) {
                if store.interval == 0 {
                    ReminderDatePicker(date: $store.due).frame(height: 24)
                } else {
                    Text(store.interval == -1 ? L("Без уведомления", "No alert") : L("Через \(store.interval / 60) мин", "In \(store.interval / 60) min")).foregroundColor(.gray)
                }
                Spacer(minLength: 0)
                Button(store.busy ? L("Ждём…", "Please wait…") : L("Сохранить", "Save")) {
                    store.create()
                }.disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 11)).buttonStyle(.plain)
        }.disabled(store.busy || store.storageUnavailable)
    }
    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Button(store.listTitle) { store.choosingList = true }.lineLimit(1)
                    Spacer()
                    Button("Apple ↗") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app")) }
                }.font(.system(size: 10)).buttonStyle(.plain).disabled(store.busy)
                if store.reminders.isEmpty {
                    Text(L("Сохрани текст или ссылку, чтобы вернуться к ним позже.", "Save text or a link to return to later."))
                        .font(.system(size: 12)).foregroundColor(.gray).padding(.vertical, 25)
                }
                ForEach(store.ordered) { reminder in row(reminder) }
                if !store.completed.isEmpty {
                    Text(L("Готово · последние 6 часов", "Completed · last 6 hours")).font(.system(size: 10)).foregroundColor(.gray).padding(.top, 5)
                    ForEach(store.completed) { reminder in row(reminder) }
                }
            }
        }
    }
    private func row(_ reminder: AppleReminder) -> some View {
        HStack(spacing: 9) {
            Button { store.show(reminder.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.text).font(.system(size: 12)).lineLimit(1).strikethrough(reminder.isCompleted)
                    dateLabel(reminder).font(.system(size: 10))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                if reminder.isCompleted {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { store.reopen(reminder.id) }
                } else {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { _ = checking.insert(reminder.id) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.18)) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            store.complete(reminder.id)
                            _ = checking.remove(reminder.id)
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle().strokeBorder(lineWidth: 1.2)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        .opacity(reminder.isCompleted || checking.contains(reminder.id) ? 1 : 0)
                        .scaleEffect(reminder.isCompleted || checking.contains(reminder.id) ? 1 : 0.6)
                }.frame(width: 18, height: 18).padding(3).contentShape(Rectangle())
            }.accessibilityLabel(!reminder.isCompleted ? L("Отметить готово", "Mark complete") : L("Вернуть в невыполненные", "Mark incomplete"))
                .disabled(checking.contains(reminder.id))
            if reminder.isCompleted {
                Button { deleting = reminder.id } label: { Image(systemName: "trash") }.accessibilityLabel(L("Удалить напоминание", "Delete reminder"))
            }
        }.buttonStyle(.plain).padding(9)
            .foregroundColor(!reminder.isCompleted ? .white : .gray)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).disabled(store.busy)
    }
    @ViewBuilder private func dateLabel(_ reminder: AppleReminder) -> some View {
        if let due = reminder.due {
            if reminder.hasTime { Text(due, style: .date) + Text(" · ") + Text(due, style: .time) }
            else { Text(due, style: .date) }
        } else { Text(L("Без даты", "No date")) }
    }
    private func detail(_ reminder: AppleReminder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                if let url = reminder.link {
                    Button {
                        if !NSWorkspace.shared.open(url) { store.message = L("Не удалось открыть ссылку.", "Could not open the link.") }
                    } label: {
                        Text(reminder.text).underline().frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).help(L("Открыть ссылку в браузере", "Open link in browser"))
                } else {
                    Text(reminder.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.font(.system(size: 13)).frame(maxHeight: .infinity)
            HStack {
                dateLabel(reminder)
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer(minLength: 0)
                Button(L("Изменить", "Edit")) { store.edit(reminder) }
                if !reminder.isCompleted {
                    Button(L("Готово", "Done")) { store.complete(reminder.id) }
                } else {
                    Button(L("Вернуть", "Restore")) { store.reopen(reminder.id) }
                    Button(L("Удалить", "Delete")) { deleting = reminder.id }
                }
            }

        }.font(.system(size: 11)).buttonStyle(.plain).disabled(store.busy)
    }
}
