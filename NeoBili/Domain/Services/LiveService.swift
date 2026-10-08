import Foundation

/// Live operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct LiveService: Sendable {
    var recommendedOperation: @Sendable (Int) async throws -> LiveRoomPage = { _ in throw ServiceError.unconfigured("Live.recommended") }
    var followedOperation: @Sendable (Int) async throws -> LiveRoomPage = { _ in throw ServiceError.unconfigured("Live.followed") }
    var followedUsersOperation: @Sendable () async throws -> LiveRoomPage = { throw ServiceError.unconfigured("Live.followedUsers") }
    var roomInfoOperation: @Sendable (Int) async throws -> LiveRoom = { _ in throw ServiceError.unconfigured("Live.roomInfo") }
    var danmuInfoOperation: @Sendable (Int) async throws -> LiveDanmuInfoPayload = { _ in throw ServiceError.unconfigured("Live.danmuInfo") }
    var superChatListOperation: @Sendable (Int) async throws -> [[String: Any]] = { _ in throw ServiceError.unconfigured("Live.superChatList") }
    var playbackOperation: @Sendable (Int, Int) async throws -> LivePlayback = { _, _ in throw ServiceError.unconfigured("Live.playback") }

    func recommended(page: Int = 1) async throws -> LiveRoomPage {
        try await recommendedOperation(page)
    }

    func followed(page: Int = 1) async throws -> LiveRoomPage {
        try await followedOperation(page)
    }

    func followedUsers() async throws -> LiveRoomPage {
        try await followedUsersOperation()
    }

    func roomInfo(roomID: Int) async throws -> LiveRoom {
        try await roomInfoOperation(roomID)
    }

    func danmuInfo(roomID: Int) async throws -> LiveDanmuInfoPayload {
        try await danmuInfoOperation(roomID)
    }

    func superChatList(roomID: Int) async throws -> [[String: Any]] {
        try await superChatListOperation(roomID)
    }

    func playback(roomID: Int, quality: Int = 10000) async throws -> LivePlayback {
        try await playbackOperation(roomID, quality)
    }
}
