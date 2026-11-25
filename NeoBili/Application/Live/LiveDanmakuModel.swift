import NeoBiliDomain
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

    struct ConnectionContext: Equatable {
        let roomID: Int
        let hasRenderedFirstFrame: Bool
        let scenePhase: ScenePhase
    }

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
    @ObservationIgnored private var pendingStart: Task<Void, Never>?
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

    func updateConnection(from previous: ConnectionContext, to current: ConnectionContext) {
        if current.scenePhase == .background, previous.scenePhase != .background {
            stop()
            return
        }
        pendingStart?.cancel()
        pendingStart = nil
        guard current.scenePhase == .active, current.roomID > 0, current.roomID != roomID else { return }
        if current.hasRenderedFirstFrame || previous.scenePhase != .active {
            start(roomID: current.roomID)
            return
        }
        // Give the first media request a head start, while keeping chat available if video stalls.
        pendingStart = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            pendingStart = nil
            start(roomID: current.roomID)
        }
    }

    func start(roomID newRoomID: Int) {
        guard newRoomID > 0, roomID != newRoomID else { return }
        stop()
        roomID = newRoomID
        connectGeneration += 1
        stream.start(roomID: newRoomID) { [weak self] event in self?.receive(event) }
        let generation = connectGeneration
        historyTask = Task { await loadSuperChats(roomID: newRoomID, generation: generation) }
    }

    func stop() {
        pendingStart?.cancel()
        pendingStart = nil
        roomID = 0
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
        case .parsed(let event): apply(event)
        }
    }

    /// 数据层已解析完成；这里只把结果转成展示值，不再接触原始 JSON。
    private func apply(_ event: LiveDanmakuParsedEvent) {
        switch event {
        case .danmaku(let payload):
            let size = payload.emoteURL.map { _ in CGSize(width: payload.emoteWidth, height: payload.emoteHeight) }
            append(message: Message(
                id: UUID().uuidString, name: payload.name, text: payload.text,
                color: payload.color, emoteURL: payload.emoteURL, emoteSize: size,
                medal: payload.medal.map { Medal(name: $0.name, level: $0.level) }
            ))
        case .superChat(let payload):
            append(superChat: payload)
        case .superChatDeleted(let ids):
            deletedSuperChatIDs.formUnion(ids)
            pruneSuperChats()
        }
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

    private func append(superChat payload: LiveDanmakuSuperChatPayload) {
        let superChat = SuperChat(
            id: payload.id,
            price: payload.price,
            message: payload.message,
            userName: payload.userName,
            faceURL: payload.faceURL,
            start: payload.start,
            end: payload.end,
            backgroundColor: Color(hex: payload.backgroundColor) ?? Color(hex: "#EDF5FF")!,
            bottomColor: Color(hex: payload.bottomColor) ?? Color(hex: "#2A60B2")!,
            priceColor: Color(hex: payload.priceColor) ?? Color(hex: "#7497CD")!,
            fontColor: Color(hex: payload.fontColor) ?? Color(hex: "#FFFFFF")!
        )
        deletedSuperChatIDs.remove(superChat.id)
        hiddenSuperChatIDs.remove(superChat.id)
        // 新 SC 置顶，历史保持服务端顺序（PiliPlus insert(0) 的等价行为）。
        superChats.removeAll { $0.id == superChat.id }
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
            guard let payload = LiveDanmakuMessageParser.superChat(from: entry),
                  !deletedSuperChatIDs.contains(payload.id),
                  !hiddenSuperChatIDs.contains(payload.id) else { continue }
            append(superChat: payload)
        }
    }

}
