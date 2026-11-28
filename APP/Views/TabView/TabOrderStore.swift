import Foundation
import SwiftUI

@MainActor
final class TabOrderStore: ObservableObject {
    static let shared = TabOrderStore()

    /// Browse · Library · Search · Signed · Settings
    static let reorderable: [TabEnum] = TabEnum.barTabs

    @Published private(set) var order: [TabEnum]

    private let storageKey = "tab_order_v8"

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        var restored = saved.compactMap(TabEnum.init(rawValue:))
        restored = restored.filter { Self.reorderable.contains($0) }
        for (index, tab) in Self.reorderable.enumerated() where !restored.contains(tab) {
            restored.insert(tab, at: min(index, restored.count))
        }
        // Prefer canonical middle Search placement when migrating from older orders.
        if !saved.contains("search") || restored != Self.reorderable {
            let hasCustomOrder = !saved.isEmpty && Set(saved) == Set(Self.reorderable.map(\.rawValue))
            if !hasCustomOrder {
                restored = Self.reorderable
            }
        }
        if restored.isEmpty {
            restored = Self.reorderable
        }
        order = restored
    }

    func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func reset() {
        order = Self.reorderable
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: storageKey)
    }
}
