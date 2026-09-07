import SwiftUI

extension EnvironmentValues {
    @Entry var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue
}

private struct VideoResolutionBatch: Equatable {
    let ids: [String]
    let generation: Int
    let enabled: Bool
    let minimumSeconds: Int
}

/// 列表持有整批判断和补页；全部完成后才发布统一的动画起点。
private struct PortraitVideoResolution<Video: VideoDimensionProviding>: ViewModifier {
    @Environment(\.hidesPortraitVideos) private var enabled
    let videos: [Video]
    let batchID: Int
    let loadReplacementPage: (@MainActor () async -> [Video])?
    @State private var entranceClock = VideoEntranceClock()
    @State private var previousBatch: VideoResolutionBatch?
    @State private var targetCount = 0
    @State private var replacing = false
    @State private var replacementPages = 0
    @State private var preparing = false

    private func identifiers(_ videos: [Video]) -> [String] {
        videos.enumerated().map { $0.element.dimensionLookupBVID ?? "unavailable-\($0.offset)" }
    }

    private var batch: VideoResolutionBatch {
        VideoResolutionBatch(ids: identifiers(videos), generation: batchID, enabled: enabled,
                             minimumSeconds: VideoDurationFilterSettings.shared.minimumSeconds)
    }

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.videoEntranceClocks) {
                $0.append(VideoEntranceScope(ids: Set(batch.ids), generation: batchID, clock: entranceClock))
            }
            .overlay {
                if preparing, entranceClock.starts.isEmpty, !videos.isEmpty {
                    LoadingTaskAnchor()
                }
            }
            .task(id: batch) {
                let current = batch
                let currentIDs = Set(current.ids)
                let previousIDs = Set(previousBatch?.ids ?? [])
                let reset = previousBatch == nil || previousBatch?.generation != batchID
                    || previousBatch?.enabled != enabled || previousBatch?.minimumSeconds != current.minimumSeconds
                    || !previousIDs.isSubset(of: currentIDs)
                if reset {
                    targetCount = videos.count
                    replacementPages = 0
                } else if !replacing {
                    targetCount += currentIDs.subtracting(previousIDs).count
                    replacementPages = 0
                }
                previousBatch = current
                replacing = false
                preparing = true
                entranceClock.prepare(ids: currentIDs, generation: batchID, reset: reset)

                if enabled || current.minimumSeconds > 0 {
                    let requests = videos.compactMap {
                        $0.metadataRequest(hidingPortrait: enabled, minimumSeconds: current.minimumSeconds)
                    }
                    await PortraitVideoStore.shared.resolveRequests(requests)
                }
                guard !Task.isCancelled else { return }
                let approved = videos.hidingKnownPortraitVideos(enabled)
                if (enabled || current.minimumSeconds > 0), approved.count < targetCount, let loadReplacementPage, replacementPages < 8 {
                    replacementPages += 1
                    replacing = true
                    let updated = await loadReplacementPage()
                    guard !Task.isCancelled else { return }
                    // 新列表的 task 继续判断补位批次。无新数据、到底或失败时，发布已有结果。
                    // 使用接口完成后的实际快照，避免依赖 SwiftUI 取消旧 task 的时机。
                    if identifiers(updated) != current.ids { return }
                    replacing = false
                }
                entranceClock.admit(approved.compactMap(\.dimensionLookupBVID))
                preparing = false
            }
    }
}

extension View {
    func resolvePortraitVideos<S: Sequence>(
        _ videos: S,
        batchID: Int = 0,
        loadReplacementPage: (@MainActor () async -> [S.Element])? = nil
    ) -> some View where S.Element: VideoDimensionProviding {
        modifier(PortraitVideoResolution(videos: Array(videos), batchID: batchID,
                                         loadReplacementPage: loadReplacementPage))
    }
}
