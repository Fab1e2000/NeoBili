extension VideoSummary { var dimensionLookupBVID: String? { bvid } }
extension SearchResultItem { var dimensionLookupBVID: String? { bvid } }
extension FollowedVideo { var dimensionLookupBVID: String? { bvid } }
extension FavMedia { var dimensionLookupBVID: String? { isVideo ? bvid : nil } }
extension HistoryItem { var dimensionLookupBVID: String? { isVideo ? history.bvid : nil } }
extension WatchLaterItem { var dimensionLookupBVID: String? { bvid } }
extension UgcSeasonEpisode { var dimensionLookupBVID: String? { bvid } }
extension SpaceVideo { var dimensionLookupBVID: String? { bvid } }
extension VideoDetail { var dimensionLookupBVID: String? { bvid } }

extension VideoSummary { var videoDurationSeconds: Int? { duration } }

extension SearchResultItem { var videoDurationSeconds: Int? { VideoDurationFilterSettings.seconds(from: duration) } }

extension FollowedVideo { var videoDurationSeconds: Int? { VideoDurationFilterSettings.seconds(from: durationText) } }

extension FavMedia { var videoDurationSeconds: Int? { duration } }

extension HistoryItem { var videoDurationSeconds: Int? { duration } }

extension WatchLaterItem { var videoDurationSeconds: Int? { duration } }

extension UgcSeasonEpisode { var videoDurationSeconds: Int? { arc?.duration } }

extension SpaceVideo { var videoDurationSeconds: Int? { VideoDurationFilterSettings.seconds(from: length) } }

extension VideoDetail { var videoDurationSeconds: Int? { duration } }
