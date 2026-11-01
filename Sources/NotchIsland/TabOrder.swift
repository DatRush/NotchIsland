import Foundation

struct TabOrder {
    static func normalized(_ saved: [String], available: [String]) -> [String] {
        var result: [String] = []
        for item in saved + available where available.contains(item) && !result.contains(item) {
            result.append(item)
        }
        return result
    }

    static func moving(_ source: String, to target: String, in order: [String]) -> [String] {
        guard let from = order.firstIndex(of: source), let to = order.firstIndex(of: target), from != to else { return order }
        var result = order
        result.remove(at: from)
        result.insert(source, at: to)
        return result
    }
}
