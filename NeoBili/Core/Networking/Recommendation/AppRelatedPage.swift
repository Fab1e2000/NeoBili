import Foundation

struct AppRelatedPage {
    let videos: [VideoSummary]
    let pagination: Data?
    let canLoadMore: Bool

    static func viewRequest(bvid: String, aid: Int, entry: PlaybackEntry, playbackSession: String, accountSession: UUID) -> Data {
        let source = entry.parameters(for: accountSession)
        let args = AppProto.integer(1, 32) + AppProto.integer(3, 84948)
        return AppProto.integer(1, aid) + AppProto.string(2, bvid)
            + AppProto.string(3, source["from"]) + AppProto.string(4, "united.player-video-detail.0.0")
            + AppProto.string(5, source["from_spmid"]) + AppProto.string(6, playbackSession)
            + AppProto.bytes(7, args) + AppProto.string(8, source["track_id"])
            + AppProto.bytes(11, AppProto.bytes(2, Data()))
    }
    static func moreRequest(bvid: String, aid: Int, entry: PlaybackEntry, playbackSession: String, accountSession: UUID, pagination: Data) -> Data {
        let source = entry.parameters(for: accountSession)
        return AppProto.integer(1, aid) + AppProto.string(2, bvid)
            + AppProto.string(3, source["from"]) + AppProto.string(4, "united.player-video-detail.0.0")
            + AppProto.string(5, source["from_spmid"])
            + AppProto.bytes(6, AppProto.integer(1, 32) + AppProto.integer(3, 84948))
            + AppProto.bytes(7, pagination) + AppProto.string(8, playbackSession)
            + AppProto.string(10, source["track_id"])
    }
    init(payload: Data, isView: Bool, accountSession: UUID) throws {
        let response = try AppProto(payload)
        if isView, response.number(8) != 0 {
            throw BiliAPIError.apiError(code: response.number(8), message: "视频不可用")
        }
        var cards: [AppProto] = []
        var cursor: Data?
        var more = false
        if isView {
            for tab in response.messages(5).flatMap({ $0.messages(1) }) {
                for module in tab.messages(2).flatMap({ $0.messages(2) }) {
                    for relates in module.messages(22) {
                        cards += relates.messages(1)
                        if let config = relates.messages(2).first { cursor = config.data(3); more = config.number(4) != 0 }
                    }
                }
            }
        } else {
            cards = response.messages(1); cursor = response.data(2)
            more = cursor.flatMap { try? AppProto($0).text(2) }?.isEmpty == false
        }
        pagination = cursor; canLoadMore = more
        videos = cards.compactMap { card in
            guard card.number(1) == 1, let basic = card.messages(12).first, let av = card.messages(2).first,
                  let title = basic.text(1), let cover = basic.text(3), basic.number(12) > 0,
                  let bvid = AppRecommendationPage.bvid(aid: basic.number(12)) else { return nil }
            let owner = basic.messages(11).first
            let stat = av.messages(4).first
            let dimension = av.messages(3).first
            var video = VideoSummary(bvid: bvid, aid: basic.number(12), cid: av.number(2), title: title, pic: cover,
                desc: basic.text(2) ?? "", duration: av.number(1), pubdate: 0,
                owner: VideoOwner(mid: owner?.number(12) ?? 0, name: owner?.text(3) ?? "", face: owner?.text(11) ?? ""),
                stat: VideoStat(view: stat?.messages(1).first?.number(1) ?? 0,
                    danmaku: stat?.messages(2).first?.number(1) ?? 0, like: stat?.number(7) ?? 0,
                    favorite: stat?.number(4) ?? 0, coin: stat?.number(5) ?? 0, share: stat?.number(6) ?? 0, reply: stat?.number(3) ?? 0))
            if let dimension { video.dimension = VideoDimension(width: dimension.number(1), height: dimension.number(2), rotate: dimension.number(3)) }
            video.playbackEntry = PlaybackEntry(source: .related, trackID: basic.text(5), reportFlowData: basic.text(15), loginSessionID: accountSession)
            return video
        }
    }
}
