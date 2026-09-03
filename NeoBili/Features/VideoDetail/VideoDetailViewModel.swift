import Foundation

@MainActor
@Observable
final class VideoDetailViewModel {
    let bvid: String
    private(set) var detail: VideoDetail?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// 官方相关视频推流。它和详情是两个独立的请求，谁先回来先显示谁，
    /// 所以相关视频不会被详情接口拖慢，反过来也一样。
    private(set) var related: [VideoSummary] = []
    private(set) var isLoadingRelated = false

    init(bvid: String) {
        self.bvid = bvid
    }

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            // 搜索卡片如果已经预取过详情，这里会直接读取缓存，不再重复请求。
            detail = try await VideoPreparationCache.shared.detail(for: bvid)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadRelated() async {
        guard related.isEmpty, !isLoadingRelated else { return }
        isLoadingRelated = true
        // 相关视频加载失败只是少一块内容，不该让整个视频页显示成错误页。
        related = (try? await BiliAPI.relatedVideos(bvid: bvid)) ?? []
        isLoadingRelated = false
    }
}
