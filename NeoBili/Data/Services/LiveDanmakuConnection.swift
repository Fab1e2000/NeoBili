import Foundation

/// Owns one room connection, authentication, heartbeats and reconnect cancellation.
@MainActor
final class LiveDanmakuConnection: LiveDanmakuStreaming {
    private var roomID = 0
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveLoop: Task<Void, Never>?
    private var connectGeneration = 0
    private var onEvent: (@MainActor (LiveDanmakuEvent) -> Void)?
    private var connection: LiveDanmakuConnectionState = .idle {
        didSet { onEvent?(.connection(connection)) }
    }

    func start(roomID: Int, onEvent: @escaping @MainActor (LiveDanmakuEvent) -> Void) {
        stop()
        self.roomID = roomID
        self.onEvent = onEvent
        receiveLoop = Task { await connect() }
    }

    func stop() {
        connectGeneration += 1
        heartbeatTask?.cancel(); heartbeatTask = nil
        receiveLoop?.cancel(); receiveLoop = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        connection = .idle
        onEvent = nil
    }

    private func connect() async {
        guard !AppNetwork.isRegression, !Task.isCancelled else { return }
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
            guard let header = LivePacketCodec.header(of: data, offset: offset),
                  header.headerLength >= 16, header.totalLength >= header.headerLength,
                  header.totalLength <= data.count - offset else { return }
            let start = data.startIndex + offset
            let body = data.subdata(in: (start + header.headerLength)..<(start + header.totalLength))
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
                onEvent?(.popularity(Int(UInt32(bigEndian: value))))
            }
        case 5:
            onEvent?(.message(body))
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

    private func send(packet data: Data) {
        // 心跳/认证丢包无需重试，走 completion 版本保持调用方同步。
        socket?.send(.data(data)) { _ in }
    }

    private static func jsonData(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }
}
