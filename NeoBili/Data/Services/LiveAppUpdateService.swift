import NeoBiliDomain
import Foundation

public extension AppUpdateService {
    static func live(
        session: URLSession,
        sourceURL: URL = AppUpdateConstants.sourceURL,
        bundleIdentifier: String = AppUpdateConstants.bundleIdentifier,
        cacheDirectory: URL? = nil
    ) -> Self {
        let directory = cacheDirectory ?? defaultPackageDirectory()
        return Self(
            fetchLatestRelease: {
                var request = URLRequest(url: sourceURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 15
                do {
                    let (data, response) = try await session.data(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw AppUpdateError.networkFailed(
                            String(localized: "更新源返回错误（HTTP \(http.statusCode)）。")
                        )
                    }
                    return try AppUpdateSourceParser.parse(
                        data: data,
                        bundleIdentifier: bundleIdentifier,
                        fallbackSourceURL: sourceURL
                    )
                } catch let error as AppUpdateError {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .cancelled {
                    throw CancellationError()
                } catch {
                    throw AppUpdateError.networkFailed(error.localizedDescription)
                }
            },
            downloadPackage: { url, version in
                LivePackageDownloader.download(
                    from: url,
                    version: version,
                    directory: directory,
                    baseConfiguration: session.configuration
                )
            },
            cleanupPackages: {
                try? FileManager.default.removeItem(at: directory)
            }
        )
    }

    private static func defaultPackageDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NeoBiliUpdates", isDirectory: true)
    }
}

private final class LivePackageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destinationURL: URL
    private var continuation: AsyncThrowingStream<AppUpdateDownloadEvent, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var finished = false

    private init(destinationURL: URL) {
        self.destinationURL = destinationURL
    }

    static func download(
        from url: URL,
        version: String,
        directory: URL,
        baseConfiguration: URLSessionConfiguration
    ) -> AsyncThrowingStream<AppUpdateDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                continuation.finish(throwing: AppUpdateError.invalidDownloadURL)
                return
            }

            let sanitizedVersion = version.map { ch -> Character in
                (ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "-" || ch == "_")) ? ch : "_"
            }
            let fileName = "NeoBili-v\(String(sanitizedVersion))-unsigned.ipa"
            let destinationURL = directory.appendingPathComponent(fileName)

            let downloader = LivePackageDownloader(destinationURL: destinationURL)
            downloader.start(url: url, baseConfiguration: baseConfiguration, continuation: continuation)

            continuation.onTermination = { _ in
                downloader.cancel()
            }
        }
    }

    private func start(
        url: URL,
        baseConfiguration: URLSessionConfiguration,
        continuation: AsyncThrowingStream<AppUpdateDownloadEvent, Error>.Continuation
    ) {
        let configuration = (baseConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 15

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let task = session.downloadTask(with: request)

        lock.lock()
        self.continuation = continuation
        self.session = session
        self.task = task
        lock.unlock()

        task.resume()
    }

    private func cancel() {
        lock.lock()
        let activeTask = task
        let activeSession = session
        let wasFinished = finished
        finished = true
        continuation = nil
        task = nil
        session = nil
        lock.unlock()

        activeTask?.cancel()
        activeSession?.invalidateAndCancel()
        if !wasFinished {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let activeContinuation = finished ? nil : continuation
        lock.unlock()

        guard let activeContinuation else { return }
        let total = max(totalBytesExpectedToWrite, 0)
        let fraction = total > 0 ? min(max(Double(totalBytesWritten) / Double(total), 0), 1) : 0
        activeContinuation.yield(.progress(fraction: fraction, completedBytes: totalBytesWritten, totalBytes: total))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            finish(with: .failure(AppUpdateError.downloadFailed(
                String(localized: "下载安装包失败（HTTP \(http.statusCode)）。")
            )))
            return
        }

        let fileManager = FileManager.default
        do {
            let directory = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)

            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                try? fileManager.removeItem(at: destinationURL)
                finish(with: .failure(AppUpdateError.downloadFailed(String(localized: "下载的安装包为空。"))))
                return
            }
            finish(with: .success(destinationURL))
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            finish(with: .failure(AppUpdateError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            finish(with: .failure(AppUpdateError.cancelled))
        } else {
            finish(with: .failure(AppUpdateError.downloadFailed(error.localizedDescription)))
        }
    }

    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let activeContinuation = continuation
        let activeSession = session
        continuation = nil
        task = nil
        session = nil
        lock.unlock()

        switch result {
        case .success(let url):
            activeContinuation?.yield(.completed(url))
            activeContinuation?.finish()
        case .failure(let error):
            try? FileManager.default.removeItem(at: destinationURL)
            activeContinuation?.finish(throwing: error)
        }
        activeSession?.finishTasksAndInvalidate()
    }
}
