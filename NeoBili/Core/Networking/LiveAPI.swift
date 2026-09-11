import Foundation

/// 仅包含浏览和播放接口；复用现有网页身份与 App 登录，不在风控后切换身份重试。
enum LiveAPI {
    static func recommended(page: Int = 1) async throws -> LiveRoomPage {
        let page = max(1, page)
        // PiliPlus 的主推荐协议也支持未登录浏览，登录时附带现有凭据。
        let accessKey = await DeviceIdentity.shared.accessKey
        let payload: LiveAppFeedPayload = try await requestApp(url: makeAppFeedURL(page: page, accessKey: accessKey))
        return payload.page(number: page)
    }

    static func followed(page: Int = 1) async throws -> LiveRoomPage {
        let page = max(1, page)
        let payload: LiveListingPayload = try await request(path: "xlive/web-ucenter/user/following", params: [
            "page": String(page), "page_size": "9", "ignoreRecord": "1", "hit_ab": "true"
        ])
        return payload.page(number: page, size: 9, onlyLive: true)
    }

    static func roomInfo(roomID: Int) async throws -> LiveRoom {
        guard roomID > 0 else { throw BiliAPIError.invalidURL }
        let payload: LiveRoomInfoPayload = try await request(path: "xlive/web-room/v1/index/getH5InfoByRoom", params: [
            "room_id": String(roomID)
        ], roomID: roomID)
        return payload.room
    }

    /// PiliPlus live.dart 的同一套播放参数，公开 nav 密钥仍由现有 WBISigner 管理。
    static func playback(roomID: Int, quality: Int = 10000) async throws -> LivePlayback {
        guard roomID > 0 else { throw BiliAPIError.invalidURL }
        let payload: LivePlaybackPayload = try await request(path: "xlive/web-room/v2/index/getRoomPlayInfo", params: [
            "room_id": String(roomID), "protocol": "0,1", "format": "0,1,2", "codec": "0,1,2",
            "qn": String(max(0, quality)), "platform": "web", "ptype": "8", "dolby": "5",
            "panorama": "1", "web_location": "444.8"
        ], roomID: roomID, signed: true)
        let playback = payload.playback(fallbackRoomID: roomID)
        if playback.isLive, playback.candidates.isEmpty {
            throw BiliAPIError.apiError(code: -1, message: "直播地址暂不可用，请稍后重试")
        }
        return playback
    }

    private static func request<T: Decodable>(path: String, params: [String: String] = [:],
                                              roomID: Int? = nil, signed: Bool = false) async throws -> T {
        let params = signed ? try await WBISigner.shared.sign(params: params) : params
        let envelope: LiveResponse<T> = try await APIClient.shared.getRaw(
            url: makeURL(path: path, params: params),
            additionalHeaders: ["Referer": "https://live.bilibili.com/" + (roomID.map(String.init) ?? "")]
        )
        return try envelope.value()
    }

    private static func requestApp<T: Decodable>(url: URL) async throws -> T {
        let envelope: LiveResponse<T> = try await APIClient.shared.getRaw(url: url, additionalHeaders: [
            "User-Agent": BiliHeaders.appUserAgent,
            "Referer": "https://live.bilibili.com/",
            // 与 APIClient.postApp 一致，App 端身份只由 access_key 表明。
            "Cookie": ""
        ])
        return try envelope.value()
    }

    static func makeAppFeedURL(page: Int, accessKey: String?, moduleSelect: Bool = false,
                               timestamp: Int = Int(Date().timeIntervalSince1970)) throws -> URL {
        var params = appBrowsingParams(page: page, accessKey: accessKey)
        if let accessKey, !accessKey.isEmpty { params["relation_page"] = "1" }
        if moduleSelect { params["module_select"] = "1" }
        return try makeAppURL(path: "xlive/app-interface/v2/index/feed", params: params, timestamp: timestamp)
    }

    private static func appBrowsingParams(page: Int, accessKey: String?) -> [String: String] {
        // 字段来自 PiliPlus http/live.dart:202–230；HD 版本与 statistics 则对应
        // common/constants.dart:16–19，保持本项目已有 App 身份配置一致。
        var params = [
            "actionKey": "appkey", "channel": "master",
            "build": "2001100", "version": "2.0.1", "mobi_app": "android_hd", "platform": "android",
            "page": String(max(1, page)), "c_locale": "zh_CN", "s_locale": "zh_CN",
            "https_url_req": "1", "fnval": "912", "disable_rcmd": "0",
            "device": "android", "device_name": "android", "device_type": "0", "network": "wifi", "scale": "2",
            "statistics": #"{"appId":5,"platform":3,"version":"2.0.1","abtest":""}"#
        ]
        if let accessKey, !accessKey.isEmpty { params["access_key"] = accessKey }
        return params
    }

    private static func makeAppURL(path: String, params: [String: String], timestamp: Int) throws -> URL {
        let signed = AppSigner.signed(params, timestamp: timestamp)
        // AppSigner 的签名编码与 WBI 不同，共用它的序列化以保持签名字节一致。
        guard var components = URLComponents(string: "https://api.live.bilibili.com/" + path) else {
            throw BiliAPIError.invalidURL
        }
        components.percentEncodedQuery = AppSigner.queryString(from: signed)
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        return url
    }

    static func makeURL(path: String, params: [String: String]) throws -> URL {
        guard var components = URLComponents(string: "https://api.live.bilibili.com/" + path) else {
            throw BiliAPIError.invalidURL
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        components.percentEncodedQueryItems = params.sorted { $0.key < $1.key }.map { key, value in
            URLQueryItem(name: key, value: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        return url
    }
}

/// App 主推荐混合房间、横幅、关注和分区入口，只提取实际的小卡片房间。
/// 对应 PiliPlus models_new/live/live_feed_index/data.dart 的 small_card_v1 分支。
struct LiveAppFeedPayload: Decodable {
    let rooms: [LiveRoom]
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        let cards = (try? values.decode([Card].self, forKey: LiveCodingKey("card_list"))) ?? []
        var seen = Set<Int>()
        rooms = cards.compactMap(\.room).filter { seen.insert($0.roomID).inserted }
        hasMore = values.liveInt("has_more").map { $0 != 0 } ?? (rooms.count >= 20)
    }

    func page(number: Int) -> LiveRoomPage {
        LiveRoomPage(rooms: rooms, page: number, hasMore: hasMore)
    }

    private struct Card: Decodable {
        let room: LiveRoom?

        init(from decoder: Decoder) throws {
            guard let values = try? decoder.container(keyedBy: LiveCodingKey.self),
                  values.liveString("card_type") == "small_card_v1",
                  let data = try? values.nestedContainer(keyedBy: LiveCodingKey.self, forKey: LiveCodingKey("card_data")) else {
                room = nil
                return
            }
            room = try? data.decode(LiveRoom.self, forKey: LiveCodingKey("small_card_v1"))
        }
    }
}

/// 直播成功响应 message 可能为数字 0，鉴权失败的 data 也可能是空数组。
struct LiveResponse<Payload: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: Payload?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        guard let code = values.liveInt("code") else {
            throw DecodingError.keyNotFound(LiveCodingKey("code"), .init(codingPath: decoder.codingPath, debugDescription: "直播响应缺少code"))
        }
        self.code = code
        message = values.liveString("message", "msg") ?? "直播服务返回错误"
        // 先保留错误码，不让失败响应的数据形状遮住未登录／风控提示。
        data = code == 0 ? try values.decodeIfPresent(Payload.self, forKey: LiveCodingKey("data")) : nil
    }

    func value() throws -> Payload {
        if [-352, -412].contains(code) { throw BiliAPIError.riskControlled }
        guard code == 0 else { throw BiliAPIError.apiError(code: code, message: message) }
        guard let data else { throw BiliAPIError.apiError(code: code, message: "直播响应缺少数据") }
        return data
    }
}

struct LiveListingPayload: Decodable {
    let rooms: [LiveRoom]
    let rawCount: Int
    let hasMore: Bool?
    let totalPage: Int?
    let total: Int?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        let items = (try? values.decode([LiveListingItem].self, forKey: LiveCodingKey("list"))) ?? []
        rawCount = items.count
        var seen = Set<Int>()
        rooms = items.compactMap(\.room).filter { seen.insert($0.roomID).inserted }
        hasMore = values.liveInt("has_more", "hasMore").map { $0 != 0 }
        totalPage = values.liveInt("totalPage", "total_page")
        total = values.liveInt("count", "total")
    }

    func page(number: Int, size: Int, onlyLive: Bool = false) -> LiveRoomPage {
        let more = hasMore ?? totalPage.map { number < $0 } ?? total.map { number * size < $0 } ?? (rawCount >= size)
        return LiveRoomPage(rooms: onlyLive ? rooms.filter(\.isLive) : rooms, page: number, hasMore: more,
                            total: total, sourceRoomIDs: rooms.map(\.roomID))
    }

    private struct LiveListingItem: Decodable {
        let room: LiveRoom?
        init(from decoder: Decoder) throws { room = try? LiveRoom(from: decoder) }
    }
}

struct LiveRoomInfoPayload: Decodable {
    let room: LiveRoom

    private struct Anchor: Decodable {
        let base_info: Base
        struct Base: Decodable { let uname: String?; let face: String? }
    }
    private struct News: Decodable { let content: String? }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        let base = try values.decode(LiveRoom.self, forKey: LiveCodingKey("room_info"))
        let anchor = try? values.decode(Anchor.self, forKey: LiveCodingKey("anchor_info"))
        let news = try? values.decode(News.self, forKey: LiveCodingKey("news_info"))
        room = LiveRoom(roomID: base.roomID, title: base.title, username: anchor?.base_info.uname ?? base.username,
                        uid: base.uid, coverURL: base.coverURL, faceURL: liveImageURL(anchor?.base_info.face) ?? base.faceURL,
                        online: base.online, areaName: base.areaName, liveStatus: base.liveStatus,
                        description: base.description, announcement: news?.content ?? base.announcement)
    }
}

/// 仅解码播放所需字段，保留服务端签名URL，不推算或篡改清晰度路径。
struct LivePlaybackPayload: Decodable {
    let room_id: Int?
    let live_status: Int
    let is_portrait: Bool?
    let playurl_info: Info?

    struct Info: Decodable { let playurl: PlayURL? }
    struct PlayURL: Decodable {
        let stream: [Stream]?
        let g_qn_desc: [Quality]?
    }
    struct Quality: Decodable { let qn: Int; let desc: String }
    struct Stream: Decodable { let protocol_name: String; let format: [Format] }
    struct Format: Decodable { let format_name: String; let codec: [Codec] }
    struct Codec: Decodable {
        let codec_name: String
        let current_qn: Int
        let accept_qn: [Int]
        let base_url: String
        let url_info: [Server]
    }
    struct Server: Decodable { let host: String; let extra: String }

    func playback(fallbackRoomID: Int) -> LivePlayback {
        let roomID = room_id ?? fallbackRoomID
        var candidates: [LiveStreamCandidate] = []
        var acceptedQualities = Set<Int>()
        var seen = Set<URL>()
        for stream in playurl_info?.playurl?.stream ?? [] {
            guard ["http_hls", "http_stream"].contains(stream.protocol_name) else { continue }
            for format in stream.format {
                guard ["ts", "fmp4", "flv"].contains(format.format_name) else { continue }
                for codec in format.codec {
                    acceptedQualities.formUnion(codec.accept_qn)
                    acceptedQualities.insert(codec.current_qn)
                    for server in codec.url_info {
                        guard !codec.base_url.isEmpty,
                              let url = URL(string: server.host + codec.base_url + server.extra),
                              let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil,
                              seen.insert(url).inserted else { continue }
                        candidates.append(LiveStreamCandidate(
                            url: url, protocolName: stream.protocol_name, formatName: format.format_name,
                            codecName: codec.codec_name, quality: codec.current_qn,
                            headers: ["Referer": "https://live.bilibili.com/\(roomID)", "User-Agent": BiliHeaders.userAgent]
                        ))
                    }
                }
            }
        }
        // 优先兼容性最好的HLS/AVC，保留HEVC/AV1和FLV备用，不修改服务端分配的质量。
        func priority(_ candidate: LiveStreamCandidate) -> Int {
            (candidate.isHLS ? 0 : 100) + (candidate.codecName == "avc" ? 0 : candidate.codecName == "hevc" ? 10 : 20)
                + (candidate.formatName == "ts" ? 0 : 1)
        }
        candidates = candidates.enumerated().sorted {
            let first = priority($0.element), second = priority($1.element)
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)
        let descriptions = Dictionary((playurl_info?.playurl?.g_qn_desc ?? []).map { ($0.qn, $0.desc) },
                                      uniquingKeysWith: { first, _ in first })
        let qualities = acceptedQualities.sorted(by: >).map {
            LiveQuality(id: $0, name: descriptions[$0] ?? LiveQuality.defaultName(for: $0))
        }
        return LivePlayback(roomID: roomID, liveStatus: live_status, isPortrait: is_portrait ?? false,
                            qualities: qualities, candidates: live_status == 1 ? candidates : [])
    }
}
