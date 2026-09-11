import Foundation
import Observation

@MainActor
@Observable
final class LiveFeedModel {
    enum Source: String, CaseIterable, Hashable, Sendable {
        case recommended
        case following

        var title: String {
            switch self {
            case .recommended: "推荐"
            case .following: "关注"
            }
        }
    }

    private(set) var source: Source = .recommended
    private(set) var rooms: [LiveRoom] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var errorMessage: String?
    private(set) var paginationError: String?
    private(set) var loadedPage = 0
    private(set) var entranceGeneration = 0

    @ObservationIgnored private var generation = UUID()
    private struct PageBatch {
        let rooms: [LiveRoom]
        let page: Int
        let hasMore: Bool
        let sourcePageSignatures: Set<Set<Int>>
    }

    @ObservationIgnored private var stagedRefresh: PageBatch?
    @ObservationIgnored private var sourcePageSignatures: Set<Set<Int>> = []
    @ObservationIgnored private var accountSessionID: UUID?
    @ObservationIgnored private var accountIsLoggedIn = false
    @ObservationIgnored private let loader: @Sendable (Source, Int) async throws -> LiveRoomPage

    init(loader: @escaping @Sendable (Source, Int) async throws -> LiveRoomPage = { source, page in
        switch source {
        case .recommended: try await LiveAPI.recommended(page: page)
        case .following: try await LiveAPI.followed(page: page)
        }
    }) {
        self.loader = loader
    }

    /// Selection changes invalidate responses immediately, before SwiftUI starts
    /// the new .task. Even a transport that ignores cancellation cannot restore
    /// another category's rooms or pagination state.
    func select(_ source: Source) {
        guard self.source != source else { return }
        self.source = source
        reset()
    }

    func synchronizeAccount(sessionID: UUID, isLoggedIn: Bool) {
        guard accountSessionID != sessionID || accountIsLoggedIn != isLoggedIn else { return }
        accountSessionID = sessionID
        accountIsLoggedIn = isLoggedIn
        if !isLoggedIn, source == .following { source = .recommended }
        reset()
    }

    func loadInitial() async {
        guard loadedPage == 0, !isLoading, !Task.isCancelled else { return }
        await refresh()
    }

    func refresh(staged: Bool = false) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        generation = requestID
        stagedRefresh = nil
        let requestedSource = source
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil
        defer { if generation == requestID { isLoading = false } }

        do {
            guard let result = try await loadVisiblePage(
                source: requestedSource, startingAt: 1, excluding: [], signatures: [], requestID: requestID
            ) else { return }
            if staged {
                stagedRefresh = result
            } else {
                applyRefresh(result)
            }
        } catch {
            guard generation == requestID, !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Refresh keeps the old cards until their existing video-card exit effect
    /// finishes. A source/account change discards this pending snapshot.
    func commitStagedRefresh() {
        guard let result = stagedRefresh else { return }
        stagedRefresh = nil
        applyRefresh(result)
    }

    func discardStagedRefresh() {
        stagedRefresh = nil
    }

    func loadMoreIfNeeded(current room: LiveRoom) async {
        guard rooms.suffix(4).contains(where: { $0.id == room.id }), paginationError == nil else { return }
        await loadMore()
    }

    func loadMore() async {
        guard loadedPage > 0, hasMore, !isLoading, !isLoadingMore,
              stagedRefresh == nil, !Task.isCancelled else { return }
        let requestID = generation
        let requestedSource = source
        let nextPage = loadedPage + 1
        isLoadingMore = true
        paginationError = nil
        defer { if generation == requestID { isLoadingMore = false } }

        do {
            guard let result = try await loadVisiblePage(
                source: requestedSource, startingAt: nextPage, excluding: Set(rooms.map(\.id)),
                signatures: sourcePageSignatures, requestID: requestID
            ) else { return }
            rooms.append(contentsOf: result.rooms)
            loadedPage = result.page
            hasMore = result.hasMore
            sourcePageSignatures = result.sourcePageSignatures
        } catch {
            guard generation == requestID, !Task.isCancelled, !error.isCancellation else { return }
            paginationError = error.localizedDescription
        }
    }

    private func reset() {
        generation = UUID()
        stagedRefresh = nil
        sourcePageSignatures = []
        rooms = []
        loadedPage = 0
        hasMore = true
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        paginationError = nil
    }

    private func applyRefresh(_ result: PageBatch) {
        rooms = result.rooms
        loadedPage = result.page
        hasMore = result.hasMore
        sourcePageSignatures = result.sourcePageSignatures
        entranceGeneration += 1
    }

    /// Following pagination counts offline rooms too. An empty visible page is
    /// not the end; continue until a page adds a room, the server ends the list,
    /// or an actually empty/repeated source page proves there is no progress.
    private func loadVisiblePage(source: Source, startingAt page: Int, excluding existing: Set<Int>,
                                 signatures: Set<Set<Int>>, requestID: UUID) async throws -> PageBatch? {
        var page = page
        var signatures = signatures
        while true {
            try Task.checkCancellation()
            let result = try await loader(source, page)
            guard generation == requestID, !Task.isCancelled else { return nil }
            let signature = Set((result.sourceRoomIDs ?? result.rooms.map(\.roomID)).filter { $0 > 0 })
            guard !signature.isEmpty, signatures.insert(signature).inserted else {
                return PageBatch(rooms: [], page: page, hasMore: false, sourcePageSignatures: signatures)
            }
            let additions = Self.unique(result.rooms).filter { !existing.contains($0.id) }
            if !additions.isEmpty || !result.hasMore {
                return PageBatch(rooms: additions, page: page, hasMore: result.hasMore,
                                 sourcePageSignatures: signatures)
            }
            page += 1
        }
    }

    private static func unique(_ rooms: [LiveRoom]) -> [LiveRoom] {
        var seen = Set<Int>()
        return rooms.filter { $0.roomID > 0 && seen.insert($0.id).inserted }
    }
}
