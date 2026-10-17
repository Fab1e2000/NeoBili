import Foundation

/// Account and page state share a graph without requiring process-global test overrides.
@MainActor
struct ApplicationStores {
    let likes: VideoLikeStore
    let followingRead: FollowingReadStore
    let searchHistory: SearchHistory
}
