import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menu = EditingMenu.make()
let edit = menu.items[0].submenu!
let expected = [("z", "undo:"), ("z", "redo:"), ("x", "cut:"), ("c", "copy:"), ("v", "paste:"), ("a", "selectAll:")]
let items = edit.items.filter { !$0.isSeparatorItem }
precondition(items.count == expected.count)
for (item, value) in zip(items, expected) {
    precondition(item.keyEquivalent == value.0 && item.action == Selector(value.1))
    precondition(item.target == nil, "Actions must use the focused responder")
    precondition(item.keyEquivalentModifierMask == (value.1 == "redo:" ? [.command, .shift] : .command))
}
final class Receiver: NSObject {
    var count = 0
    @objc func paste(_ sender: Any?) { count += 1 }
}
let receiver = Receiver()
edit.autoenablesItems = false
let paste = items[4]
paste.target = receiver
paste.isEnabled = true
func key(_ flags: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
}
precondition(menu.performKeyEquivalent(with: key(.command)))
precondition(receiver.count == 1)
_ = menu.performKeyEquivalent(with: key([]))
_ = menu.performKeyEquivalent(with: key([.command, .option]))
precondition(receiver.count == 1)
print("PASS: standard editing actions, responder-chain targets and actual Command-V menu dispatch")
