import Foundation
import Network

enum OfflineTransferEvent: Sendable {
    case progress(String, Int64, Int64)
    case downloaded(String, URL, Int, Int64)
    case failed(String, String, Data?, Bool)
    case network(available: Bool, cellular: Bool)
    case finishedEvents(String)
}

protocol OfflineCacheTransport: Sendable {
    var events: AsyncStream<OfflineTransferEvent> { get }
    func existingTokens() async -> Set<String>
    func start(token: String, url: URL, cellular: Bool, resumeData: Data?) async throws
    func pause(token: String) async -> Data?
    func cancel(token: String) async
}

/// Delegate callbacks first move temporary files, then deliver ordered events to the repository.
final class BackgroundCacheTransport: NSObject, OfflineCacheTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    let events: AsyncStream<OfflineTransferEvent>
    private let continuation: AsyncStream<OfflineTransferEvent>.Continuation
    private let spool: URL
    private var sessions: [Bool: URLSession] = [:]
    private let monitor: NWPathMonitor?

    init(directory: URL, enabled: Bool) {
        let stream = AsyncStream<OfflineTransferEvent>.makeStream()
        events = stream.stream; continuation = stream.continuation
        spool = directory.appendingPathComponent("Transfers", isDirectory: true)
        monitor = enabled ? NWPathMonitor() : nil
        super.init()
        guard enabled else { return }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        for cellular in [false, true] {
            let suffix = cellular ? "cellular" : "wifi"
            let identifier = (Bundle.main.bundleIdentifier ?? "com.elsterlee.NeoBili") + ".offline." + suffix
            let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
            configuration.allowsCellularAccess = cellular
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
            configuration.waitsForConnectivity = true
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            sessions[cellular] = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        }
        monitor?.pathUpdateHandler = { [continuation] path in
            continuation.yield(.network(available: path.status == .satisfied, cellular: path.usesInterfaceType(.cellular)))
        }
        monitor?.start(queue: DispatchQueue(label: "NeoBili.offline.network"))
    }

    private func tasks() async -> [URLSessionTask] {
        var result: [URLSessionTask] = []
        for session in sessions.values { result += await session.allTasks }
        return result
    }

    func existingTokens() async -> Set<String> {
        Set(await tasks().compactMap(\.taskDescription))
    }

    func start(token: String, url: URL, cellular: Bool, resumeData: Data?) async throws {
        guard let session = sessions[cellular] else { throw URLError(.notConnectedToInternet) }
        var request = URLRequest(url: url)
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.httpShouldHandleCookies = false
        // Session policy controls Wi-Fi-only transfers, including resumed requests.
        request.allowsCellularAccess = true
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
        task.taskDescription = token
        task.resume()
    }

    func pause(token: String) async -> Data? {
        guard let task = await tasks().first(where: { $0.taskDescription == token }) as? URLSessionDownloadTask else { return nil }
        return await withCheckedContinuation { continuation in
            task.cancel { continuation.resume(returning: $0) }
        }
    }

    func cancel(token: String) async {
        for task in await tasks() where task.taskDescription == token { task.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let token = downloadTask.taskDescription else { return }
        continuation.yield(.progress(token, totalBytesWritten, totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let token = downloadTask.taskDescription else { return }
        do {
            try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let saved = spool.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: saved)
            let rangeTotal = (downloadTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range")?
                .split(separator: "/").last.flatMap { Int64($0) }
            continuation.yield(.downloaded(token, saved,
                (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0,
                rangeTotal ?? downloadTask.response?.expectedContentLength ?? -1))
        } catch {
            continuation.yield(.failed(token, error.localizedDescription, nil,
                (error as NSError).code == NSFileWriteOutOfSpaceError))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let token = task.taskDescription else { return }
        let ns = error as NSError
        continuation.yield(.failed(token, error.localizedDescription,
            ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
            ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let identifier = session.configuration.identifier { continuation.yield(.finishedEvents(identifier)) }
    }
}
