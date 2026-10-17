extension VideoSummary { public var dimensionLookupBVID: String? { bvid } }
extension SearchResultItem { public var dimensionLookupBVID: String? { bvid } }
extension FollowedVideo { public var dimensionLookupBVID: String? { bvid } }
extension FavMedia { public var dimensionLookupBVID: String? { isVideo ? bvid : nil } }
extension HistoryItem { public var dimensionLookupBVID: String? { isVideo ? history.bvid : nil } }
extension WatchLaterItem { public var dimensionLookupBVID: String? { bvid } }
extension UgcSeasonEpisode { public var dimensionLookupBVID: String? { bvid } }
extension SpaceVideo { public var dimensionLookupBVID: String? { bvid } }
extension VideoDetail { public var dimensionLookupBVID: String? { bvid } }

extension VideoSummary {
    public var videoDurationSeconds: Int? { duration }
    /// 推荐里的直播、图文卡不是视频，画幅和时长过滤都不该挡住它们。
    public var skipsVideoFilters: Bool { recommendationTarget != nil }
}

extension SearchResultItem { public var videoDurationSeconds: Int? { VideoDuration.seconds(from: duration) } }

extension FollowedVideo { public var videoDurationSeconds: Int? { VideoDuration.seconds(from: durationText) } }

extension FavMedia { public var videoDurationSeconds: Int? { duration } }

extension HistoryItem { public var videoDurationSeconds: Int? { duration } }

extension WatchLaterItem { public var videoDurationSeconds: Int? { duration } }

extension UgcSeasonEpisode { public var videoDurationSeconds: Int? { arc?.duration } }

extension SpaceVideo { public var videoDurationSeconds: Int? { VideoDuration.seconds(from: length) } }

extension VideoDetail { public var videoDurationSeconds: Int? { duration } }
