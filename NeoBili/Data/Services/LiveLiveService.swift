import Foundation

extension LiveService {
    static func live(client: APIClient = .shared) -> Self {
        Self(
            recommendedOperation: { page in
                try await LiveAPI.recommended(page: page)
            },
            followedOperation: { page in
                try await LiveAPI.followed(page: page)
            },
            followedUsersOperation: {
                try await LiveAPI.followedUsers()
            },
            roomInfoOperation: { roomID in
                try await LiveAPI.roomInfo(roomID: roomID)
            },
            danmuInfoOperation: { roomID in
                try await LiveAPI.danmuInfo(roomID: roomID)
            },
            superChatListOperation: { roomID in
                try await LiveAPI.superChatList(roomID: roomID)
            },
            playbackOperation: { roomID, quality in
                try await LiveAPI.playback(roomID: roomID, quality: quality)
            }
        )
    }
}
