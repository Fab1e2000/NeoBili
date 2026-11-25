import NeoBiliDomain
import Foundation
import Network
import Synchronization

/// 本地轻量 HTTP 媒体代理：
/// 1. 向上游 B 站 CDN 注入 Referer / User-Agent，解决 DLNA 电视直连 403；
/// 2. 完整支持 HTTP Range（206 Partial Content），保证点播与离线缓存可自由拖动进度条；
/// 3. 重写直播 HLS (.m3u8) 分片地址，使电视拉取每个分片都经过本代理携带请求头。
actor LocalMediaProxyServer {
    enum Route: Sendable {
        case localFile(url: URL, mimeType: String)
        case remoteMedia(url: URL, headers: [String: String], mimeType: String, isHLS: Bool)
        case remoteDualTrack(videoURL: URL, audioURL: URL?, headers: [String: String], startPosition: TimeInterval)
    }

    struct ByteRange: Equatable, Sendable {
        let start: Int64
        let end: Int64
        var length: Int64 { end - start + 1 }
    }

    private let queue = DispatchQueue(label: "com.elsterlee.NeoBili.cast-proxy", qos: .userInitiated)
    private let upstreamSession: URLSession
    private var listener: NWListener?
    private var port: UInt16?
    private var routes: [String: Route] = [:]
    private var activeConnections: [UUID: Task<Void, Never>] = [:]

    init(upstreamSession: URLSession? = nil) {
        if let upstreamSession {
            self.upstreamSession = upstreamSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 0
            config.httpMaximumConnectionsPerHost = 6
            self.upstreamSession = URLSession(configuration: config)
        }
    }

    func ensureStarted() async throws -> UInt16 {
        if let port, listener != nil {
            return port
        }
        let newListener: NWListener
        do {
            newListener = try NWListener(using: .tcp)
        } catch {
            throw CastError.proxyStartFailed(error.localizedDescription)
        }

        let boundPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            final class ResumeGuard: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                func claim() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return false }
                    resumed = true
                    return true
                }
            }
            let guardBox = ResumeGuard()

            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guardBox.claim() {
                        if let rawPort = newListener.port?.rawValue, rawPort > 0 {
                            continuation.resume(returning: rawPort)
                        } else {
                            continuation.resume(throwing: CastError.proxyStartFailed("无法分配本地端口"))
                        }
                    }
                case .failed(let error):
                    if guardBox.claim() {
                        continuation.resume(throwing: CastError.proxyStartFailed(error.localizedDescription))
                    }
                case .cancelled:
                    if guardBox.claim() {
                        continuation.resume(throwing: CastError.proxyStartFailed("本地服务已取消"))
                    }
                default:
                    break
                }
            }

            let session = upstreamSession
            newListener.newConnectionHandler = { [weak self, weak newListener] connection in
                let box = SendableConnectionBox(connection)
                Task { [weak self, weak newListener] in
                    guard let self, let newListener else {
                        box.connection.cancel()
                        return
                    }
                    await self.startConnection(box, from: newListener, upstreamSession: session)
                }
            }

            newListener.start(queue: queue)
        }

        listener = newListener
        port = boundPort
        return boundPort
    }

    func publish(_ route: Route, host: String) async throws -> URL {
        let boundPort = try await ensureStarted()
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        // 每次新投屏只保留当前活跃路由，避免旧链接继续占用资源。
        routes = [token: route]
        let fileName: String
        switch route {
        case .localFile(let url, _):
            let rawExt = url.pathExtension.lowercased()
            let ext = (rawExt.isEmpty || rawExt == "m4s") ? "mp4" : rawExt
            fileName = "media.\(ext)"
        case .remoteMedia(_, _, _, let isHLS):
            fileName = isHLS ? "live.m3u8" : "media.mp4"
        case .remoteDualTrack:
            fileName = "dash.mp4"
        }
        guard let url = URL(string: "http://\(host):\(boundPort)/cast/\(token)/\(fileName)") else {
            throw CastError.proxyStartFailed("无法生成本地代理地址")
        }
        return url
    }

    func stop() {
        routes.removeAll()
        for task in activeConnections.values {
            task.cancel()
        }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func startConnection(_ box: SendableConnectionBox, from source: NWListener,
                                 upstreamSession: URLSession) {
        guard listener === source else { box.connection.cancel(); return }
        let id = UUID()
        activeConnections[id] = Task.detached(priority: .userInitiated) { [weak self] in
            let connection = box.connection
            await withTaskCancellationHandler {
                guard !Task.isCancelled else { return }
                connection.start(queue: DispatchQueue.global(qos: .userInitiated))
                await Self.handleConnection(connection, server: self, upstreamSession: upstreamSession)
            } onCancel: {
                box.connection.cancel()
            }
            connection.cancel()
            await self?.removeConnection(id)
        }
    }

    private func removeConnection(_ id: UUID) {
        activeConnections.removeValue(forKey: id)
    }

    private func route(for token: String) -> Route? {
        routes[token]
    }

    // MARK: - HTTP Request Handling

    private static func handleConnection(
        _ connection: NWConnection,
        server: LocalMediaProxyServer?,
        upstreamSession: URLSession
    ) async {
        guard let rawRequest = await readHTTPRequestHeader(from: connection),
              let request = parseHTTPRequest(rawRequest) else {
            return
        }

        let method = request.method.uppercased()
        guard method == "GET" || method == "HEAD" else {
            await sendSimpleResponse(connection, status: "405 Method Not Allowed")
            return
        }

        let isHead = (method == "HEAD")
        guard let urlComponents = URLComponents(string: request.path) else {
            await sendSimpleResponse(connection, status: "400 Bad Request")
            return
        }
        let segments = urlComponents.path.split(separator: "/").map(String.init)
        guard segments.count >= 3, segments[0] == "cast" else {
            await sendSimpleResponse(connection, status: "404 Not Found")
            return
        }
        let token = segments[1]
        let leaf = segments[2]

        guard let route = await server?.route(for: token) else {
            await sendSimpleResponse(connection, status: "404 Not Found")
            return
        }

        let hostHeader = request.headers["host"]
        let proxyPrefix = hostHeader.map { "http://\($0)/cast/\(token)" } ?? "/cast/\(token)"

        if leaf == "seg",
           let encoded = urlComponents.queryItems?.first(where: { $0.name == "u" })?.value,
           let targetURL = decodeBase64URL(encoded),
           case .remoteMedia(_, let headers, _, _) = route {
            await serveRemote(
                connection: connection,
                url: targetURL,
                headers: headers,
                defaultMimeType: Self.guessMimeType(for: targetURL),
                isHLS: targetURL.pathExtension.lowercased() == "m3u8",
                proxyPrefix: proxyPrefix,
                rangeHeader: request.headers["range"],
                isHead: isHead,
                upstreamSession: upstreamSession
            )
            return
        }

        switch route {
        case .localFile(let fileURL, let mimeType):
            await serveLocalFile(
                connection: connection,
                fileURL: fileURL,
                mimeType: mimeType,
                rangeHeader: request.headers["range"],
                isHead: isHead
            )
        case .remoteMedia(let remoteURL, let headers, let mimeType, let isHLS):
            await serveRemote(
                connection: connection,
                url: remoteURL,
                headers: headers,
                defaultMimeType: mimeType,
                isHLS: isHLS,
                proxyPrefix: proxyPrefix,
                rangeHeader: request.headers["range"],
                isHead: isHead,
                upstreamSession: upstreamSession
            )
        case .remoteDualTrack(let videoURL, let audioURL, let headers, let startPosition):
            await serveRemoteDualTrack(
                connection: connection,
                videoURL: videoURL,
                audioURL: audioURL,
                headers: headers,
                startPosition: startPosition,
                isHead: isHead
            )
        }
    }

    private static func serveRemoteDualTrack(
        connection: NWConnection,
        videoURL: URL,
        audioURL: URL?,
        headers: [String: String],
        startPosition: TimeInterval,
        isHead: Bool
    ) async {
        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: video/mp4",
            "Transfer-Encoding: chunked",
            "Cache-Control: no-cache",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        guard await send(Data(header.utf8), over: connection) else { return }
        guard !isHead else { return }

        final class CancellationState: @unchecked Sendable {
            private let lock = NSLock()
            private var cancelled = false
            func cancel() {
                lock.lock()
                cancelled = true
                lock.unlock()
            }
            var isCancelled: Bool {
                lock.lock()
                defer { lock.unlock() }
                return cancelled
            }
        }
        let state = CancellationState()
        let box = SendableConnectionBox(connection)

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { continuation.resume() }
                    do {
                        try DASHCastRemuxer.stream(
                            videoURL: videoURL,
                            audioURL: audioURL,
                            headers: headers,
                            startPosition: startPosition,
                            isCancelled: { state.isCancelled },
                            onChunk: { chunk in
                                guard !state.isCancelled else { return false }
                                let frame = Self.makeHTTPChunk(chunk)
                                return Self.sendSync(frame, over: box.connection)
                            }
                        )
                        if !state.isCancelled {
                            _ = Self.sendSync(Data("0\r\n\r\n".utf8), over: box.connection)
                        }
                    } catch {
                        // 上游断开或客户端中止时静默结束连接。
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func makeHTTPChunk(_ payload: Data) -> Data {
        let prefix = String(format: "%x\r\n", payload.count)
        var framed = Data(prefix.utf8)
        framed.append(payload)
        framed.append(Data("\r\n".utf8))
        return framed
    }

    private static func sendSync(_ data: Data, over connection: NWConnection) -> Bool {
        final class ResultBox: @unchecked Sendable { var ok = false }
        let result = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        connection.send(content: data, completion: .contentProcessed { error in
            result.ok = (error == nil)
            semaphore.signal()
        })
        semaphore.wait()
        return result.ok
    }

    private static func serveLocalFile(
        connection: NWConnection,
        fileURL: URL,
        mimeType: String,
        rangeHeader: String?,
        isHead: Bool
    ) async {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = (attrs[.size] as? NSNumber)?.int64Value,
              fileSize >= 0 else {
            await sendSimpleResponse(connection, status: "404 Not Found")
            return
        }

        var byteRange: ByteRange?
        if let rangeHeader {
            guard let parsed = parseByteRange(rangeHeader, totalLength: fileSize) else {
                let header = [
                    "HTTP/1.1 416 Range Not Satisfiable",
                    "Content-Range: bytes */\(fileSize)",
                    "Content-Length: 0",
                    "Connection: close",
                    "",
                    ""
                ].joined(separator: "\r\n")
                _ = await send(Data(header.utf8), over: connection)
                return
            }
            byteRange = parsed
        }

        let start = byteRange?.start ?? 0
        let length = byteRange?.length ?? fileSize
        var headerLines: [String] = []
        if let byteRange {
            headerLines.append("HTTP/1.1 206 Partial Content")
            headerLines.append("Content-Range: bytes \(byteRange.start)-\(byteRange.end)/\(fileSize)")
        } else {
            headerLines.append("HTTP/1.1 200 OK")
        }
        headerLines.append("Content-Type: \(mimeType)")
        headerLines.append("Content-Length: \(length)")
        headerLines.append("Accept-Ranges: bytes")
        headerLines.append("Connection: close")
        headerLines.append("")
        headerLines.append("")

        guard await send(Data(headerLines.joined(separator: "\r\n").utf8), over: connection) else { return }
        guard !isHead, length > 0 else { return }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(start))
        } catch {
            return
        }

        var remaining = length
        let chunkSize = 65_536
        while remaining > 0, !Task.isCancelled {
            let toRead = Int(min(Int64(chunkSize), remaining))
            guard let chunk = try? handle.read(upToCount: toRead), !chunk.isEmpty else { break }
            guard await send(chunk, over: connection) else { break }
            remaining -= Int64(chunk.count)
        }
    }

    private static func serveRemote(
        connection: NWConnection,
        url: URL,
        headers: [String: String],
        defaultMimeType: String,
        isHLS: Bool,
        proxyPrefix: String,
        rangeHeader: String?,
        isHead: Bool,
        upstreamSession: URLSession
    ) async {
        var upstreamRequest = URLRequest(url: url)
        upstreamRequest.httpMethod = isHead && !isHLS ? "HEAD" : "GET"
        for (key, value) in headers {
            upstreamRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let rangeHeader, !isHLS {
            upstreamRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        if isHLS {
            do {
                let (data, response) = try await upstreamSession.data(for: upstreamRequest)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    await sendSimpleResponse(connection, status: "502 Bad Gateway")
                    return
                }
                let playlist = String(decoding: data, as: UTF8.self)
                let finalBase = http.url ?? url
                let rewritten = rewriteHLSPlaylist(playlist, baseURL: finalBase, proxyPrefix: proxyPrefix)
                let payload = Data(rewritten.utf8)
                let header = [
                    "HTTP/1.1 200 OK",
                    "Content-Type: application/vnd.apple.mpegurl",
                    "Content-Length: \(payload.count)",
                    "Cache-Control: no-cache",
                    "Connection: close",
                    "",
                    ""
                ].joined(separator: "\r\n")
                guard await send(Data(header.utf8), over: connection) else { return }
                if !isHead {
                    _ = await send(payload, over: connection)
                }
            } catch {
                await sendSimpleResponse(connection, status: "502 Bad Gateway")
            }
            return
        }

        let (events, continuation) = AsyncThrowingStream<UpstreamEvent, any Error>.makeStream()
        let delegate = UpstreamDelegate(continuation: continuation)
        let task = upstreamSession.dataTask(with: upstreamRequest)
        task.delegate = delegate
        defer { task.cancel() }
        var sentHeaders = false
        do {
            try Task.checkCancellation()
            task.resume()
            var stream = events.makeAsyncIterator()
            let response = try await stream.next()
            try Task.checkCancellation()
            guard case .response(let http)? = response else {
                await sendSimpleResponse(connection, status: "502 Bad Gateway")
                return
            }
            let statusCode = http.statusCode
            let reason = HTTPURLResponse.localizedString(forStatusCode: statusCode)
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? defaultMimeType

            var headerLines = [
                "HTTP/1.1 \(statusCode) \(reason)",
                "Content-Type: \(contentType)",
                "Accept-Ranges: bytes",
                "Connection: close"
            ]
            if let contentLength = http.value(forHTTPHeaderField: "Content-Length") {
                headerLines.append("Content-Length: \(contentLength)")
            }
            if let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
                headerLines.append("Content-Range: \(contentRange)")
            }
            headerLines.append("")
            headerLines.append("")

            sentHeaders = true
            guard await send(Data(headerLines.joined(separator: "\r\n").utf8), over: connection) else { return }
            guard !isHead else { return }

            while case .chunk(let data)? = try await stream.next() {
                try Task.checkCancellation()
                guard await send(data, over: connection) else { return }
                delegate.didForward(data.count, from: task)
            }
        } catch {
            if !sentHeaders, !Task.isCancelled {
                await sendSimpleResponse(connection, status: "502 Bad Gateway")
            }
        }
    }

    private enum UpstreamEvent: Sendable {
        case response(HTTPURLResponse)
        case chunk(Data)
    }

    private final class UpstreamDelegate: NSObject, URLSessionDataDelegate {
        private struct Flow {
            var pendingBytes = 0
            var suspended = false
            var finished = false
        }

        private let flow = Mutex(Flow())
        private let continuation: AsyncThrowingStream<UpstreamEvent, any Error>.Continuation

        init(continuation: AsyncThrowingStream<UpstreamEvent, any Error>.Continuation) {
            self.continuation = continuation
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            guard let response = response as? HTTPURLResponse else {
                continuation.finish(throwing: URLError(.badServerResponse))
                completionHandler(.cancel)
                return
            }
            continuation.yield(.response(response))
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            flow.withLock { flow in
                flow.pendingBytes += data.count
                // URLSession may already have queued more callbacks. Keep those chunks
                // and pause new reads until the downstream sends catch up.
                if !flow.suspended, flow.pendingBytes >= 256 * 1024 {
                    flow.suspended = true
                    dataTask.suspend()
                }
            }
            continuation.yield(.chunk(data))
        }

        func didForward(_ count: Int, from task: URLSessionDataTask) {
            flow.withLock { flow in
                flow.pendingBytes -= count
                if !flow.finished, flow.suspended, flow.pendingBytes <= 128 * 1024 {
                    flow.suspended = false
                    task.resume()
                }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            flow.withLock { $0.finished = true }
            continuation.finish(throwing: error)
        }
    }

    // MARK: - Pure Helpers (Testable)

    struct ParsedHTTPRequest: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
    }

    static func parseHTTPRequest(_ raw: String) -> ParsedHTTPRequest? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return ParsedHTTPRequest(method: method, path: path, headers: headers)
    }

    static func parseByteRange(_ header: String, totalLength: Int64) -> ByteRange? {
        guard totalLength > 0 else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = String(trimmed.dropFirst("bytes=".count))
            .split(separator: ",").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let dash = spec.firstIndex(of: "-") else { return nil }
        let startPart = String(spec[..<dash])
        let endPart = String(spec[spec.index(after: dash)...])

        if startPart.isEmpty {
            // suffix range: bytes=-500
            guard let suffix = Int64(endPart), suffix > 0 else { return nil }
            let start = max(0, totalLength - suffix)
            return ByteRange(start: start, end: totalLength - 1)
        }
        guard let start = Int64(startPart), start >= 0, start < totalLength else { return nil }
        if endPart.isEmpty {
            return ByteRange(start: start, end: totalLength - 1)
        }
        guard let rawEnd = Int64(endPart), rawEnd >= start else { return nil }
        return ByteRange(start: start, end: min(rawEnd, totalLength - 1))
    }

    static func rewriteHLSPlaylist(_ playlist: String, baseURL: URL, proxyPrefix: String) -> String {
        let lines = playlist.components(separatedBy: .newlines)
        let rewritten = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            if trimmed.hasPrefix("#") {
                return rewriteTagURI(in: line, baseURL: baseURL, proxyPrefix: proxyPrefix)
            }
            guard let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
                return line
            }
            return "\(proxyPrefix)/seg?u=\(encodeBase64URL(resolved))"
        }
        return rewritten.joined(separator: "\n")
    }

    private static func rewriteTagURI(in line: String, baseURL: URL, proxyPrefix: String) -> String {
        guard let uriRange = line.range(of: "URI=\"") else { return line }
        let afterOpen = uriRange.upperBound
        guard let closeQuote = line[afterOpen...].firstIndex(of: "\"") else { return line }
        let rawURI = String(line[afterOpen..<closeQuote])
        guard let resolved = URL(string: rawURI, relativeTo: baseURL)?.absoluteURL else { return line }
        let replacement = "\(proxyPrefix)/seg?u=\(encodeBase64URL(resolved))"
        var result = line
        result.replaceSubrange(afterOpen..<closeQuote, with: replacement)
        return result
    }

    static func encodeBase64URL(_ url: URL) -> String {
        Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ encoded: String) -> URL? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func guessMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": "application/vnd.apple.mpegurl"
        case "ts": "video/mp2t"
        case "m4s", "mp4": "video/mp4"
        case "flv": "video/x-flv"
        default: "application/octet-stream"
        }
    }

    // MARK: - Low-Level NWConnection I/O

    private static func readHTTPRequestHeader(from connection: NWConnection) async -> String? {
        var accumulated = Data()
        let delimiter = Data("\r\n\r\n".utf8)
        let maxHeaderBytes = 32_768

        while accumulated.count < maxHeaderBytes, !Task.isCancelled {
            let chunk: Data? = await withCheckedContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete || error != nil {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            guard let chunk else { return nil }
            if chunk.isEmpty { continue }
            accumulated.append(chunk)
            if let range = accumulated.range(of: delimiter) {
                return String(decoding: accumulated[..<range.upperBound], as: UTF8.self)
            }
        }
        return nil
    }

    private static func send(_ data: Data, over connection: NWConnection) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private static func sendSimpleResponse(_ connection: NWConnection, status: String) async {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = await send(Data(response.utf8), over: connection)
    }
}

private final class SendableConnectionBox: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) {
        self.connection = connection
    }
}
