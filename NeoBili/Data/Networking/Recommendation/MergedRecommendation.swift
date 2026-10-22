#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

/// BiliPai's app-first interleave, adapted to NeoBili's iOS credential scope.
/// Each side retains its own pagination and attribution; no Android credentials are borrowed.
enum MergedRecommendation {
    static func combine(request: RecommendationRequest,
                        app: Result<RecommendationBatch, Error>,
                        web: Result<RecommendationBatch, Error>) throws -> RecommendationBatch {
        for result in [app, web] {
            if case .failure(let error) = result,
               error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            if case .failure(let error as BiliAPIError) = result {
                switch error {
                case .missingAccessKey, .apiError(code: -101, message: _): throw error
                default: break
                }
            }
        }
        let appBatch = try? app.get()
        let webBatch = try? web.get()
        let appVideos = appBatch?.videos ?? []
        let webVideos = webBatch?.videos ?? []
        if appVideos.isEmpty && webVideos.isEmpty {
            if case .failure(let error) = app { throw error }
            if case .failure(let error) = web { throw error }
        }
        var seen = Set<String>()
        var videos: [VideoSummary] = []
        for index in 0..<max(appVideos.count, webVideos.count) {
            for list in [appVideos, webVideos] where index < list.count {
                let video = list[index]
                if seen.insert(video.bvid).inserted { videos.append(video) }
            }
        }
        var next = request.next(appCursor: request.appCursor)
        if let appBatch {
            next.appFinished = appBatch.nextRequest == nil
            if let continuation = appBatch.nextRequest {
                next.appCursor = continuation.appCursor
                next.appPageIndex = continuation.pageIndex
            }
        }
        if let webBatch {
            next.webFinished = webBatch.nextRequest == nil
            if let continuation = webBatch.nextRequest { next.webPageIndex = continuation.pageIndex }
        }
        return RecommendationBatch(videos: videos,
            nextRequest: next.appFinished && next.webFinished ? nil : next,
            refreshConfig: appBatch?.refreshConfig, appCursor: next.appCursor,
            refreshCursor: appBatch?.refreshCursor, exposurePolicy: appBatch?.exposurePolicy)
    }
}

extension BiliAPI {
    static func mergedRecommendFeed(request: RecommendationRequest, client: APIClient, identity: DeviceIdentity,
                                    session: AppRecommendationSession, network: AppNetworkMetadata,
                                    clickReporter: RecommendationClickReporter,
                                    filter: @Sendable () -> RecommendationFilter) async throws -> RecommendationBatch {
        let account = try await client.appAccount()
        // Do not silently turn a logged-in app feed into anonymous or web-only recommendations.
        if account.mid != nil, account.accessKey?.isEmpty != false { throw BiliAPIError.missingAccessKey }
        let empty = RecommendationBatch(videos: [], nextRequest: nil)
        async let app: Result<RecommendationBatch, Error> = captureRecommendation {
            guard !request.appFinished else { return empty }
            return try await appRecommendFeed(request: .init(source: .app, pageIndex: request.appPageIndex,
                appCursor: request.appCursor, isRefresh: request.isRefresh), client: client, identity: identity,
                session: session, network: network, clickReporter: clickReporter, filter: filter,
                expectedSessionID: account.sessionID)
        }
        async let web: Result<RecommendationBatch, Error> = captureRecommendation {
            guard !request.webFinished else { return empty }
            return try await webRecommendationBatch(request: .init(source: .web, pageIndex: request.webPageIndex),
                merged: true, expectedSessionID: account.sessionID, client: client, filter: filter)
        }
        let results = await (app, web)
        try Task.checkCancellation()
        _ = try await client.appAccount(expectedSessionID: account.sessionID)
        return try MergedRecommendation.combine(request: request, app: results.0, web: results.1)
    }

    private static func captureRecommendation(_ operation: @Sendable () async throws -> RecommendationBatch)
        async -> Result<RecommendationBatch, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}
