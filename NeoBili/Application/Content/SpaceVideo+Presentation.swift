import Foundation

extension SpaceVideo {
    func asFollowedVideo(avatar: String) -> FollowedVideo {
        FollowedVideo(
            id: bvid,
            bvid: bvid,
            aid: aid,
            title: title,
            cover: pic,
            durationText: length,
            playText: play > 0 ? play.biliCountText : "",
            authorMid: mid,
            authorName: author,
            authorFace: avatar,
            publishedText: created > 0 ? created.biliRelativeTimeText : "",
            dimension: dimension
        )
    }
}
