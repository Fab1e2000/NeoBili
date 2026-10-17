import Foundation

public struct VideoResolutionBatch: Equatable {
    public let ids: [String]
    public let generation: Int
    public let enabled: Bool
    public let minimumSeconds: Int

    public func resetsEntrance(comparedTo previous: Self?) -> Bool {
        guard let previous else { return true }
        // ID 增删仅影响对应卡片；只有主动刷新或过滤设置变化才重播整批。
        return generation != previous.generation
            || enabled != previous.enabled
            || minimumSeconds != previous.minimumSeconds
    }

    public init(
        ids: [String],
        generation: Int,
        enabled: Bool,
        minimumSeconds: Int
    ) {
        self.ids = ids
        self.generation = generation
        self.enabled = enabled
        self.minimumSeconds = minimumSeconds
    }
}

