import Foundation
import NeoBiliDomain

@MainActor @Observable
final class SpaceCollectionDetailModel {
    let collection: SpaceCollectionSummary
    let filtering: VideoFilterDependencies
    let list: SpaceCollectionPagination<SpaceCollectionArchive>

    private let mid: Int
    private let services: ApplicationServices
    private(set) var sortReverse: Bool

    var archives: [SpaceCollectionArchive] { list.items }

    init(collection: SpaceCollectionSummary, hostMID: Int, services: ApplicationServices,
         filtering: VideoFilterDependencies) {
        self.collection = collection
        self.filtering = filtering
        self.services = services
        mid = collection.mid > 0 ? collection.mid : hostMID
        let newestFirst = true
        sortReverse = newestFirst
        list = SpaceCollectionPagination(order: Self.archiveOrder(newestFirst: newestFirst))
    }

    func loadIfNeeded() async {
        guard !list.hasLoadedCurrentOrder else { return }
        await reload()
    }

    func reload() async { await list.reload(fetchPage) }

    func toggleSort() {
        sortReverse.toggle()
        list.resetForNewOrder(Self.archiveOrder(newestFirst: sortReverse))
    }

    private static func archiveOrder(newestFirst: Bool) -> (SpaceCollectionArchive, SpaceCollectionArchive) -> Bool {
        { first, second in
            // 发布时间未知的稿件放在末尾，同一时间的稿件沿用服务端顺序。
            if first.pubdate <= 0 { return false }
            if second.pubdate <= 0 { return true }
            return newestFirst ? first.pubdate > second.pubdate : first.pubdate < second.pubdate
        }
    }

    func stageRefresh() async -> Bool { await list.stageRefresh(fetchPage) }
    func commitRefresh() { list.commitRefresh() }
    func discardRefresh() { list.discardRefresh() }

    func loadMoreIfNeeded(current: SpaceCollectionArchive, hidingKnownPortraitVideos enabled: Bool) async {
        guard list.paginationError == nil else { return }
        let visible = archives.hidingKnownPortraitVideos(enabled, filtering: filtering)
        guard visible.suffix(5).contains(where: { $0.id == current.id }) else { return }
        await loadReplacementPage()
    }

    func loadReplacementPage() async { await list.loadMore(fetchPage) }

    private func fetchPage(_ page: Int, loadedCount: Int) async throws -> SpaceCollectionPagination<SpaceCollectionArchive>.Page {
        let result: SpaceCollectionArchivePage
        switch collection.kind {
        case .season:
            result = try await services.community.spaceSeasonArchives(
                mid: mid, seasonID: collection.collectionID, page: page, sortReverse: sortReverse)
        case .series:
            result = try await services.community.spaceSeriesArchives(
                mid: mid, seriesID: collection.collectionID, page: page, sortReverse: sortReverse)
        }
        return .init(items: result.archives, rawItemCount: result.rawItemCount, number: result.pageNumber,
                     hasMore: result.hasMore(after: loadedCount + result.rawItemCount, requestedPage: page))
    }
}
