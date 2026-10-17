#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension LiveService {
    static func live(client: APIClient, identity: DeviceIdentity, session: URLSession) -> Self {
        Self(
            recommendedOperation: { page in
                try await LiveAPI.recommended(page: page, client: client, identity: identity)
            },
            followedOperation: { page in
                try await LiveAPI.followed(page: page, client: client)
            },
            followedUsersOperation: {
                try await LiveAPI.followedUsers(client: client)
            },
            roomInfoOperation: { roomID in
                try await LiveAPI.roomInfo(roomID: roomID, client: client)
            },
            danmuInfoOperation: { roomID in
                try await LiveAPI.danmuInfo(roomID: roomID, client: client)
            },
            superChatListOperation: { roomID in
                try await LiveAPI.superChatList(roomID: roomID, session: session)
            },
            playbackOperation: { roomID, quality in
                try await LiveAPI.playback(roomID: roomID, quality: quality, client: client)
            }
        )
    }
}
