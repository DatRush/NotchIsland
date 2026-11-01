import Foundation
let tabs = ["home", "music", "focus", "screenshot"]
precondition(TabOrder.normalized([], available: tabs) == tabs)
precondition(TabOrder.normalized(["music", "music", "removed"], available: tabs) == ["music", "home", "focus", "screenshot"])
let moved = TabOrder.moving("home", to: "screenshot", in: tabs)
precondition(moved == ["music", "focus", "screenshot", "home"])
precondition(TabOrder.moving("screenshot", to: "home", in: tabs) == ["screenshot", "home", "music", "focus"])
precondition(TabOrder.moving("missing", to: "home", in: tabs) == tabs)
precondition(TabOrder.moving("home", to: "home", in: tabs) == tabs)
let suite = "NotchIsland.TabOrder.Checks." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set(moved, forKey: "sectionOrder")
precondition(TabOrder.normalized(defaults.stringArray(forKey: "sectionOrder")!, available: tabs) == moved)
print("PASS: default order, migration, deduplication, moving in both directions, no-op, persisted order")
