import AppKit

/// Standard AppKit editing actions use the focused responder, including WebKit.
/// Accessory apps need this menu even though they do not show a normal menu bar.
enum EditingMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let item = NSMenuItem(title: L("Правка", "Edit"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: L("Правка", "Edit"))
        edit.addItem(withTitle: L("Отменить", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("Повторить", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Вырезать", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Копировать", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Вставить", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Выделить всё", "Select All"), action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        item.submenu = edit
        main.addItem(item)
        return main
    }
}
