import Foundation
import SwiftUI

/// 直播间弹幕与 SC 的展示状态；连接生命周期由注入的实时通道负责。
///
/// 协议对齐 PiliPlus（lib/tcp/live.dart）：`getDanmuInfo` 拿 token 与服务器列表，
/// WebSocket 认证包 protover 2（zlib 压缩，iOS 用系统 Compression 解，不引第三方），
/// 30 秒心跳，op=5 的 JSON 消息里只消费 `DANMU_MSG` 与 SC 两类——其余
/// （进场、礼物、舰长）按 PiliPlus 的默认行为静默丢弃。
@MainActor
@Observable
final class LiveDanmakuModel {
    typealias SuperChatLoader = @MainActor (Int) async throws -> [[String: Any]]
    struct Medal: Hashable, Sendable {
        let name: String
        let level: Int
    }

    struct Message: Identifiable, Sendable {
        let id: String
        let name: String
        let text: String
        /// 服务端下发的弹幕颜色（ARGB）；nil 用默认白色。
        let color: UInt32?
        /// 表情弹幕（dm_type=1）的图片与原始尺寸。
        let emoteURL: URL?
        let emoteSize: CGSize?
        let medal: Medal?
    }

    struct SuperChat: Identifiable, Sendable {
        let id: Int
        let price: Int
        let message: String
        let userName: String
        let faceURL: URL?
        let start: TimeInterval
        let end: TimeInterval
        let backgroundColor: Color
        let bottomColor: Color
        let priceColor: Color
        let fontColor: Color

        func remaining(at now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval { end - now }
        var isValid: Bool { remaining() > 0 }
        func bannerDuration(at now: TimeInterval) -> TimeInterval { max(0, min(10, remaining(at: now))) }
    }

    typealias ConnectionState = LiveDanmakuConnectionState

    private(set) var messages: [Message] = []
    private(set) var superChats: [SuperChat] = []
    private(set) var popularity: Int?
    private(set) var connection: ConnectionState = .idle

    /// 全屏飘幕引擎由 overlay 挂载；新弹幕到达时直接推给它。
    private weak var flowEngine: DanmakuEngine?
    private var hiddenSuperChatIDs: Set<Int> = []
    private var deletedSuperChatIDs: Set<Int> = []

    private var roomID = 0
    @ObservationIgnored private let stream: any LiveDanmakuStreaming
    private var connectGeneration = 0
    @ObservationIgnored private var historyTask: Task<Void, Never>?
    @ObservationIgnored private let superChatLoader: SuperChatLoader
    @ObservationIgnored private var pendingMessages: [Message] = []
    @ObservationIgnored private var messageFlushTask: Task<Void, Never>?

    static let messageLimit = 200
    private static let messageTrimmedCount = 150

    init(stream: any LiveDanmakuStreaming = ApplicationServices.makeLiveDanmakuStream(), superChatLoader: @escaping SuperChatLoader = { try await ApplicationServices.live.streaming.superChatList(roomID: $0) }) {
        self.stream = stream
        self.superChatLoader = superChatLoader
    }

    // MARK: - 生命周期

    func start(roomID newRoomID: Int) {
        guard newRoomID > 0 else { return }
        guard roomID != newRoomID || connection == .idle else { return }
        stop()
        roomID = newRoomID
        connectGeneration += 1
        stream.start(roomID: newRoomID) { [weak self] event in self?.receive(event) }
        let generation = connectGeneration
        historyTask = Task { await loadSuperChats(roomID: newRoomID, generation: generation) }
    }

    func stop() {
        connectGeneration += 1
        stream.stop()
        historyTask?.cancel()
        historyTask = nil
        connection = .idle
        messageFlushTask?.cancel()
        messageFlushTask = nil
        pendingMessages.removeAll(keepingCapacity: true)
        messages = []
        superChats = []
        popularity = nil
        // A reconnect can keep the same mounted fullscreen renderer. Its weak
        // attachment belongs to the representable lifecycle, not the socket.
        flowEngine?.clear(keepTimelineAt: 0)
        hiddenSuperChatIDs = []
        deletedSuperChatIDs = []
    }

    func attach(flowEngine engine: DanmakuEngine) { flowEngine = engine }
    func detach(flowEngine engine: DanmakuEngine) {
        if self.flowEngine === engine { flowEngine = nil }
    }

    func hideSuperChat(_ id: Int) { hiddenSuperChatIDs.insert(id); pruneSuperChats() }

    // MARK: - 连接

    func receive(_ event: LiveDanmakuEvent) {
        switch event {
        case .connection(let state): connection = state
        case .popularity(let value): popularity = value
        case .message(let body): parse(messageJSON: body)
        }
    }

    /// op=5 的 JSON 消息。只消费 DANMU_MSG 与 SC；其他 cmd 按 PiliPlus 默认忽略。
    private func parse(messageJSON body: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let command = root["cmd"] as? String else { return }
        if command.hasPrefix("DANMU_MSG") {
            append(danmaku: root["info"])
        } else if command == "SUPER_CHAT_MESSAGE" {
            if let data = root["data"] { append(superChat: data) }
        } else if command == "SUPER_CHAT_MESSAGE_DELETE" {
            // 官方下架的 SC 立即移除（PiliPlus 注释掉了这段，这里按协议实现）。
            if let data = root["data"] as? [String: Any],
               let ids = data["ids"] as? [Int] {
                deletedSuperChatIDs.formUnion(ids)
                pruneSuperChats()
            }
        }
    }

    private func append(danmaku info: Any?) {
        guard let info = info as? [Any?], info.count > 2 else { return }
        let text = info[1] as? String ?? ""
        guard !text.isEmpty else { return }

        let legacyUser = info[2] as? [Any] ?? []
        var name = legacyUser.count > 1 ? legacyUser[1] as? String ?? "" : ""
        var medal: Medal?
        var emote: URL?
        var emoteSize: CGSize?
        let header = info[0] as? [Any?] ?? []
        var color: UInt32? = header.count > 3 ? (header[3] as? UInt32) : nil
        if let first = info[0] as? [Any?], first.count > 15,
           let content = first[15] as? [String: Any] {
            if let user = content["user"] as? [String: Any] {
                name = (user["base"] as? [String: Any])?["name"] as? String ?? name
                if let medalValue = user["medal"] as? [String: Any],
                   let medalName = medalValue["name"] as? String, !medalName.isEmpty {
                    medal = Medal(name: medalName, level: medalValue["level"] as? Int ?? 0)
                }
            }
            // extra 是一段内嵌 JSON 字符串：颜色、表情弹幕类型与表情表都在里面。
            if let extraText = content["extra"] as? String,
               let extra = try? JSONSerialization.jsonObject(with: Data(extraText.utf8)) as? [String: Any] {
                if let raw = extra["color"] as? Int { color = UInt32(bitPattern: Int32(truncatingIfNeeded: raw)) }
                let isEmote = extra["dm_type"] as? Int == 1
                if isEmote, let emots = extra["emots"] as? [String: Any],
                   let match = emots[text] as? [String: Any],
                   let urlString = match["url"] as? String {
                    emote = URL(string: urlString)
                    emoteSize = CGSize(width: match["width"] as? Int ?? 0, height: match["height"] as? Int ?? 0)
                }
            }
            // 大表情（整条弹幕就是一张图）在 info[0][13]。
            if emote == nil, let big = first[13] as? [String: Any],
               let urlString = big["url"] as? String, !urlString.isEmpty {
                emote = URL(string: urlString)
                emoteSize = CGSize(width: big["width"] as? Int ?? 0, height: big["height"] as? Int ?? 0)
            }
        }
        guard !name.isEmpty else { return }
        let message = Message(id: UUID().uuidString, name: name, text: text, color: color,
                              emoteURL: emote, emoteSize: emoteSize, medal: medal)
        append(message: message)
    }

    func append(message: Message) {
        // The fullscreen renderer stays real-time. Only the SwiftUI history list
        // coalesces bursts, so it does not diff 200 rows for every network message.
        flowEngine?.enqueue(text: message.text, color: message.color ?? 0xFF_FFFF)
        pendingMessages.append(message)
        if pendingMessages.count > Self.messageLimit {
            pendingMessages.removeFirst(pendingMessages.count - Self.messageTrimmedCount)
        }
        guard messageFlushTask == nil else { return }
        messageFlushTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            self?.flushMessages()
        }
    }

    func flushMessages() {
        messageFlushTask?.cancel()
        messageFlushTask = nil
        guard !pendingMessages.isEmpty else { return }
        var updated = messages + pendingMessages
        pendingMessages.removeAll(keepingCapacity: true)
        if updated.count > Self.messageLimit {
            updated.removeFirst(updated.count - Self.messageTrimmedCount)
        }
        messages = updated
    }

    private func append(superChat value: Any?) {
        guard let data = value as? [String: Any],
              let id = data["id"] as? Int,
              let price = data["price"] as? Int,
              let message = data["message"] as? String else { return }
        let userInfo = data["user_info"] as? [String: Any] ?? [:]
        let superChat = SuperChat(
            id: id,
            price: price,
            message: message,
            userName: userInfo["uname"] as? String ?? "",
            faceURL: (userInfo["face"] as? String).flatMap(URL.init),
            start: data["start_time"] as? Double ?? Date().timeIntervalSince1970,
            end: data["end_time"] as? Double ?? Date().timeIntervalSince1970,
            backgroundColor: Color(hex: data["background_color"] as? String) ?? Color(hex: "#EDF5FF")!,
            bottomColor: Color(hex: data["background_bottom_color"] as? String) ?? Color(hex: "#2A60B2")!,
            priceColor: Color(hex: data["background_price_color"] as? String) ?? Color(hex: "#7497CD")!,
            fontColor: Color(hex: data["message_font_color"] as? String) ?? Color(hex: "#FFFFFF")!
        )
        deletedSuperChatIDs.remove(id)
        hiddenSuperChatIDs.remove(id)
        // 新 SC 置顶，历史保持服务端顺序（PiliPlus insert(0) 的等价行为）。
        superChats.removeAll { $0.id == id }
        superChats.insert(superChat, at: 0)
        pruneSuperChats()
    }

    /// SC 一次开播可能很多：只保留有效期内且未被删除/关闭的最新几条。
    private func pruneSuperChats() {
        superChats = superChats.filter { item in
            item.isValid && !deletedSuperChatIDs.contains(item.id) && !hiddenSuperChatIDs.contains(item.id)
        }
        if superChats.count > 5 { superChats.removeLast(superChats.count - 5) }
    }

    private func loadSuperChats(roomID: Int, generation: Int) async {
        guard generation == connectGeneration, !Task.isCancelled else { return }
        let list = (try? await superChatLoader(roomID)) ?? []
        // stop()/重连之后返回的结果不能再进已清空的列表。
        guard generation == connectGeneration, !Task.isCancelled, !list.isEmpty else { return }
        // 服务端按时间正序；append 是「新条目插到最前」，所以正序迭代后
        // 最新的排在最前，prune 的 removeLast 丢的也是最旧的。
        for entry in list {
            append(superChat: entry)
        }
    }

}
