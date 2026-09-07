import Foundation
import Observation

/// 删除跨越动画和网络等待时只保存 ID；快照版本避免旧刷新把已删除条目放回来。
@MainActor
@Observable
final class ListRemovalState<ID: Hashable> {
    private(set) var hiddenIDs: Set<ID> = []
    private(set) var revision = UUID()
    private var pendingIDs: Set<ID> = []

    func begin(_ id: ID) -> Bool {
        guard pendingIDs.insert(id).inserted else { return false }
        revision = UUID()
        return true
    }

    func hide(_ id: ID) { hiddenIDs.insert(id) }

    func finish(_ id: ID) {
        pendingIDs.remove(id)
        hiddenIDs.remove(id)
        revision = UUID()
    }

    @discardableResult
    func remove<Item: Identifiable>(_ id: ID, from items: inout [Item]) -> Int? where Item.ID == ID {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        items.removeAll { $0.id == id }
        return index
    }

    func restore<Item: Identifiable>(_ item: Item, at index: Int, in items: inout [Item]) where Item.ID == ID {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: min(max(index, 0), items.count))
    }
}
