import Foundation

/// Live operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct LiveService: Sendable {
    public var recommendedOperation: @Sendable (Int) async throws -> LiveRoomPage = { _ in throw ServiceError.unconfigured("Live.recommended") }
    public var followedOperation: @Sendable (Int) async throws -> LiveRoomPage = { _ in throw ServiceError.unconfigured("Live.followed") }
    public var followedUsersOperation: @Sendable () async throws -> LiveRoomPage = { throw ServiceError.unconfigured("Live.followedUsers") }
    public var roomInfoOperation: @Sendable (Int) async throws -> LiveRoom = { _ in throw ServiceError.unconfigured("Live.roomInfo") }
    public var danmuInfoOperation: @Sendable (Int) async throws -> LiveDanmuInfoPayload = { _ in throw ServiceError.unconfigured("Live.danmuInfo") }
    public var superChatListOperation: @Sendable (Int) async throws -> [[String: Any]] = { _ in throw ServiceError.unconfigured("Live.superChatList") }
    public var playbackOperation: @Sendable (Int, Int) async throws -> LivePlayback = { _, _ in throw ServiceError.unconfigured("Live.playback") }

    public func recommended(page: Int = 1) async throws -> LiveRoomPage {
        try await recommendedOperation(page)
    }

    public func followed(page: Int = 1) async throws -> LiveRoomPage {
        try await followedOperation(page)
    }

    public func followedUsers() async throws -> LiveRoomPage {
        try await followedUsersOperation()
    }

    public func roomInfo(roomID: Int) async throws -> LiveRoom {
        try await roomInfoOperation(roomID)
    }

    public func danmuInfo(roomID: Int) async throws -> LiveDanmuInfoPayload {
        try await danmuInfoOperation(roomID)
    }

    public func superChatList(roomID: Int) async throws -> [[String: Any]] {
        try await superChatListOperation(roomID)
    }

    public func playback(roomID: Int, quality: Int = 10000) async throws -> LivePlayback {
        try await playbackOperation(roomID, quality)
    }

    public init(
        recommendedOperation: @escaping @Sendable (Int) async throws -> LiveRoomPage = { _ in throw ServiceError.unconfigured("Live.recommended") },
        followedOperation: @escaping @Sendable (Int) async throws -> LiveRoomPage = { _ in throw ServiceError.unconfigured("Live.followed") },
        followedUsersOperation: @escaping @Sendable () async throws -> LiveRoomPage = { throw ServiceError.unconfigured("Live.followedUsers") },
        roomInfoOperation: @escaping @Sendable (Int) async throws -> LiveRoom = { _ in throw ServiceError.unconfigured("Live.roomInfo") },
        danmuInfoOperation: @escaping @Sendable (Int) async throws -> LiveDanmuInfoPayload = { _ in throw ServiceError.unconfigured("Live.danmuInfo") },
        superChatListOperation: @escaping @Sendable (Int) async throws -> [[String: Any]] = { _ in throw ServiceError.unconfigured("Live.superChatList") },
        playbackOperation: @escaping @Sendable (Int, Int) async throws -> LivePlayback = { _, _ in throw ServiceError.unconfigured("Live.playback") }
    ) {
        self.recommendedOperation = recommendedOperation
        self.followedOperation = followedOperation
        self.followedUsersOperation = followedUsersOperation
        self.roomInfoOperation = roomInfoOperation
        self.danmuInfoOperation = danmuInfoOperation
        self.superChatListOperation = superChatListOperation
        self.playbackOperation = playbackOperation
    }
}
