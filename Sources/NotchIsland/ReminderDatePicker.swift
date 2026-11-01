import AppKit
import SwiftUI

// Keep all date editing in the island window. A calendar overlay uses another
// window and conflicts with the island's deliberate outside-click dismissal.
final class InlineReminderDatePicker: NSDatePicker {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct ReminderDatePicker: NSViewRepresentable {
    @Binding var date: Date
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> InlineReminderDatePicker {
        let picker = InlineReminderDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.datePickerMode = .single
        picker.presentsCalendarOverlay = false
        picker.drawsBackground = false
        picker.isBordered = false
        picker.font = .systemFont(ofSize: 11)
        picker.textColor = .white
        picker.controlSize = .small
        picker.locale = AppLanguage.locale
        picker.setAccessibilityLabel(L("Дата и время напоминания", "Reminder date and time"))
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.dateValue = date
        return picker
    }
    func updateNSView(_ picker: InlineReminderDatePicker, context: Context) {
        picker.locale = AppLanguage.locale
        picker.setAccessibilityLabel(L("Дата и время напоминания", "Reminder date and time"))
        context.coordinator.parent = self
        picker.isEnabled = context.environment.isEnabled
        if picker.dateValue != date { picker.dateValue = date }
    }
    final class Coordinator: NSObject {
        var parent: ReminderDatePicker
        init(_ parent: ReminderDatePicker) { self.parent = parent }
        @objc func changed(_ picker: NSDatePicker) { parent.date = picker.dateValue }
    }
}
