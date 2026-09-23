import Foundation
import SwiftUI

/// 直播间弹幕与 SC 的实时通道。
///
/// 协议对齐 PiliPlus（lib/tcp/live.dart）：`getDanmuInfo` 拿 token 与服务器列表，
/// WebSocket 认证包 protover 2（zlib 压缩，iOS 用系统 Compression 解，不引第三方），
/// 30 秒心跳，op=5 的 JSON 消息里只消费 `DANMU_MSG` 与 SC 两类——其余
/// （进场、礼物、舰长）按 PiliPlus 的默认行为静默丢弃。
@MainActor
@Observable
final class LiveDanmakuModel {
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
    }

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
    }

    private(set) var messages: [Message] = []
    private(set) var superChats: [SuperChat] = []
    private(set) var popularity: Int?
    private(set) var connection: ConnectionState = .idle

    /// 全屏飘幕引擎由 overlay 挂载；新弹幕到达时直接推给它。
    private weak var flowEngine: DanmakuEngine?
    private var hiddenSuperChatIDs: Set<Int> = []
    private var deletedSuperChatIDs: Set<Int> = []

    private var roomID = 0
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveLoop: Task<Void, Never>?
    private var connectGeneration = 0
    private var isLoadingHistory = false
    @ObservationIgnored private var pendingMessages: [Message] = []
    @ObservationIgnored private var messageFlushTask: Task<Void, Never>?

    static let messageLimit = 200
    private static let messageTrimmedCount = 150

    // MARK: - 生命周期

    func start(roomID newRoomID: Int) {
        guard newRoomID > 0 else { return }
        guard roomID != newRoomID || connection == .idle else { return }
        stop()
        roomID = newRoomID
        connectGeneration += 1
        receiveLoop = Task { await connect() }
        Task { await loadSuperChats() }
    }

    func stop() {
        connectGeneration += 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        connection = .idle
        messageFlushTask?.cancel()
        messageFlushTask = nil
        pendingMessages.removeAll(keepingCapacity: true)
        messages = []
        superChats = []
        popularity = nil
        flowEngine = nil
        hiddenSuperChatIDs = []
        deletedSuperChatIDs = []
    }

    func attach(flowEngine engine: DanmakuEngine) { flowEngine = engine }
    func detach(flowEngine engine: DanmakuEngine) {
        if self.flowEngine === engine { flowEngine = nil }
    }

    func hideSuperChat(_ id: Int) { hiddenSuperChatIDs.insert(id); pruneSuperChats() }

    // MARK: - 连接

    private func connect() async {
        let generation = connectGeneration
        connection = .connecting
        // 服务器列表逐个尝试；每个候选 8 秒内没完成认证就换下一个。
        guard let info = try? await LiveAPI.danmuInfo(roomID: roomID), !info.hosts.isEmpty else {
            scheduleReconnect(generation: generation)
            return
        }
        guard generation == connectGeneration else { return }
        let identity = await DeviceIdentity.shared.accountSnapshot()
        guard generation == connectGeneration else { return }
        ensureSession()
        for host in info.hosts {
            guard generation == connectGeneration else { return }
            guard let url = URL(string: "wss://\(host.host):\(host.wssPort)/sub") else { continue }
            heartbeatTask?.cancel()
            heartbeatTask = nil
            var request = URLRequest(url: url)
            request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            let task = session?.webSocketTask(with: request)
            socket = task
            task?.resume()
            let timeout = Task { [weak task] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, generation == self.connectGeneration,
                      self.connection != .connected else { return }
                task?.cancel(with: .goingAway, reason: nil)
            }
            defer { timeout.cancel() }

            let auth: [String: Any] = [
                "uid": identity.accountID ?? 0, "roomid": roomID, "protover": 2,
                "platform": "web", "type": 2, "key": info.token
            ]
            send(packet: LivePacketCodec.packet(op: 7, protover: 1, seq: 1, body: Self.jsonData(auth)))
            // 认证回复（op=8）只能从接收循环里读到，所以循环必须立刻跑起来：
            // 8 秒内收到 op8 就一直收下去（正常工作状态），否则换下一个 host。
            if await runReceiveLoop(generation: generation, authDeadline: Date().addingTimeInterval(8)) {
                return
            }
            task?.cancel(with: .goingAway, reason: nil)
            connection = .connecting
        }
        scheduleReconnect(generation: generation)
    }

    /// 模型生命周期内复用同一个 URLSession；stop() 时统一 invalidate。
    private func ensureSession() {
        guard session == nil else { return }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    private func scheduleReconnect(generation: Int) {
        guard generation == connectGeneration else { return }
        connection = .connecting
        receiveLoop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, generation == self.connectGeneration else { return }
            await self.connect()
        }
    }

    /// 接收主循环。
    ///
    /// 认证阶段（`authDeadline` 非 nil）8 秒内没等到 op=8 就返回 false；
    /// 认证通过后循环常驻，连接断开/出错时返回 false（或 generation 失效直接退出）。
    /// 返回 true 仅表示「仍在正常接收」——调用方据此停在当前 host 上。
    private func runReceiveLoop(generation: Int, authDeadline: Date?) async -> Bool {
        var deadline = authDeadline
        while generation == connectGeneration, !Task.isCancelled {
            if connection != .connected, let deadline, Date() > deadline { return false }
            guard let socket else { return false }
            do {
                let message = try await socket.receive()
                guard generation == connectGeneration else { return true }
                switch message {
                case .data(let data):
                    handleFrame(data)
                case .string(let text):
                    handleText(text)
                @unknown default:
                    break
                }
                if connection == .connected, heartbeatTask == nil {
                    startHeartbeat()
                }
                if connection == .connected { deadline = nil }
            } catch {
                guard generation == connectGeneration else { return true }
                return false
            }
        }
        return connection == .connected
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            var sequence: UInt32 = 1
            while !Task.isCancelled {
                self?.send(packet: LivePacketCodec.packet(op: 2, protover: 1, seq: sequence))
                sequence += 1
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - 帧解析

    func handleFrame(_ data: Data) {
        var offset = 0
        while data.count - offset >= 16 {
            let remaining = data.subdata(in: offset..<data.count)
            guard let header = LivePacketCodec.header(of: remaining),
                  header.headerLength >= 16, header.totalLength >= header.headerLength,
                  header.totalLength <= remaining.count else { return }
            let body = remaining.subdata(in: header.headerLength..<header.totalLength)
            switch header.protover {
            case 0, 1:
                dispatch(operation: header.operation, body: body)
            case 2:
                if let inflated = LivePacketCodec.inflate(body: body) {
                    for (operation, messageBody) in LivePacketCodec.splitConcatenated(inflated) {
                        dispatch(operation: operation, body: messageBody)
                    }
                }
            default: break
            }
            offset += header.totalLength
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        dispatch(operation: 5, body: data)
    }

    private func dispatch(operation: UInt32, body: Data) {
        switch operation {
        case 3:
            // 心跳回复：前 4 字节大端人气值。
            if body.count >= 4 {
                var value: UInt32 = 0
                body.withUnsafeBytes { value = $0.loadUnaligned(as: UInt32.self) }
                popularity = Int(UInt32(bigEndian: value))
            }
        case 5:
            parse(messageJSON: body)
        case 8:
            guard let reply = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  reply["code"] as? Int == 0 else {
                socket?.cancel(with: .policyViolation, reason: nil)
                return
            }
            if connection != .connected { connection = .connected }
        default:
            break
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

    private func loadSuperChats() async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        let roomID = roomID
        let generation = connectGeneration
        let list = (try? await LiveAPI.superChatList(roomID: roomID)) ?? []
        // stop()/重连之后返回的结果不能再进已清空的列表。
        guard generation == connectGeneration, !list.isEmpty else { return }
        // 服务端按时间正序；append 是「新条目插到最前」，所以正序迭代后
        // 最新的排在最前，prune 的 removeLast 丢的也是最旧的。
        for entry in list {
            append(superChat: entry)
        }
    }

    // MARK: - 包格式

    private func send(packet data: Data) {
        // 心跳/认证丢包无需重试，走 completion 版本保持调用方同步。
        socket?.send(.data(data)) { _ in }
    }

    private static func jsonData(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }
}

/// `getDanmuInfo` 的响应形状：认证 token 与候选弹幕服务器（wss 端口优先）。
struct LiveDanmuInfoPayload: Decodable {
    let token: String
    let hosts: [Host]

    struct Host: Decodable {
        let host: String
        let wssPort: Int
        enum CodingKeys: String, CodingKey { case host; case wssPort = "wss_port" }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        token = values.liveString("token") ?? ""
        hosts = (try? values.decode([Host].self, forKey: LiveCodingKey("host_list"))) ?? []
    }
}

// MARK: - 十六进制颜色

extension Color {
    /// SC 服务端下发 `#RRGGBB` 色串；解析失败返回 nil 由调用方给默认值。
    init?(hex: String?) {
        guard var value = hex, value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xFF) / 255,
                  green: Double((number >> 8) & 0xFF) / 255,
                  blue: Double(number & 0xFF) / 255)
    }
}
