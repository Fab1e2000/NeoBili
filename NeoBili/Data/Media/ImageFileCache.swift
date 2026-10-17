import Foundation
import ImageIO
import CryptoKit

actor ImageFileCache {
    static let shared = ImageFileCache()

    typealias Download = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let directory: URL
    private let byteLimit: Int
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date
    private let downloadData: Download
    private var inFlight: [URL: Task<URL, Error>] = [:]
    private var owners: [UUID: Set<String>] = [:]
    private struct Entry { let bytes: Int; var accessed: Date }
    private var entries: [URL: Entry] = [:]
    private var currentFiles: [String: URL] = [:]
    private var totalBytes = 0
    private var indexed = false
    private var lastExpirySweep: Date?
    private static let knownExtensions = ["jpg", "png", "gif", "webp", "heic"]

    // 文件缓存独立于 URLCache。活动查看器持有所有已请求文件（含分享面板），
    // 释放后按最近访问顺序回到预算；仅在访问/写入/释放时清理，不后台轮询。
    init(directory: URL? = nil, byteLimit: Int = 256 * 1024 * 1024,
         maxAge: TimeInterval = 30 * 24 * 60 * 60,
         now: @escaping @Sendable () -> Date = { Date() },
         download: @escaping Download = { try await AppNetwork.session.data(for: $0) }) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "ImageViewer", directoryHint: .isDirectory)
        self.byteLimit = max(0, byteLimit)
        self.maxAge = max(0, maxAge)
        self.now = now
        self.downloadData = download
    }

    func localFile(for remote: URL, owner: UUID? = nil) async throws -> URL {
        indexIfNeeded()
        if let owner { owners[owner, default: []].insert(Self.digest(of: remote)) }
        if let cached = cachedFile(for: remote) {
            touch(cached)
            return cached
        }
        if let existing = inFlight[remote] { return try await existing.value }
        trim()
        let task = Task<URL, Error> { try await download(remote) }
        inFlight[remote] = task
        defer {
            inFlight[remote] = nil
            // An unowned caller still needs its returned file. A released viewer does not.
            if let owner, owners[owner] == nil { trim() }
        }
        return try await task.value
    }

    func release(owner: UUID) {
        owners[owner] = nil
        trim()
    }

    /// 每次下载使用独立版本 URL，迟到的旧解码失败只能删除旧版本。
    func invalidate(_ remote: URL, file: URL) {
        guard file.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path,
              Self.key(for: file) == Self.digest(of: remote) else { return }
        try? FileManager.default.removeItem(at: file)
        removeEntry(file)
    }

    private func removeEntry(_ file: URL) {
        if let entry = entries.removeValue(forKey: file) { totalBytes -= entry.bytes }
        let key = Self.key(for: file)
        if currentFiles[key] == file { currentFiles[key] = nil }
    }

    private static func key(for file: URL) -> String {
        // 同时识别升级前的 digest.ext 文件。
        String(file.deletingPathExtension().lastPathComponent.split(separator: "-", maxSplits: 1)[0])
    }

    private func indexIfNeeded() {
        guard !indexed else { return }
        indexed = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])) ?? []
        for file in files where Self.knownExtensions.contains(file.pathExtension) {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            entries[file] = Entry(bytes: values.fileSize ?? 0, accessed: values.contentModificationDate ?? .distantPast)
            totalBytes += values.fileSize ?? 0
            let key = Self.key(for: file)
            if let current = currentFiles[key], let currentEntry = entries[current],
               currentEntry.accessed > (values.contentModificationDate ?? .distantPast) { continue }
            currentFiles[key] = file
        }
    }

    private func touch(_ file: URL) {
        let date = now()
        entries[file]?.accessed = date
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    private func trim(protecting files: Set<URL> = []) {
        var bytes = totalBytes
        let date = now()
        // 预算内的连续下载不重复排序；过期扫描最多随访问每分钟触发一次。
        let expiryDue = lastExpirySweep.map { date.timeIntervalSince($0) >= min(maxAge, 60) } ?? true
        guard bytes > byteLimit || expiryDue else { return }
        if expiryDue { lastExpirySweep = date }
        let protected = owners.values.reduce(into: Set<String>()) { $0.formUnion($1) }
            .union(inFlight.keys.map(Self.digest))
        let cutoff = date.addingTimeInterval(-maxAge)
        for (file, entry) in entries.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            guard !files.contains(file), !protected.contains(Self.key(for: file)),
                  bytes > byteLimit || entry.accessed < cutoff else { continue }
            do {
                try FileManager.default.removeItem(at: file)
                removeEntry(file)
                bytes -= entry.bytes
            } catch { /* Keep accounting for files that could not be removed. */ }
        }
    }

    private func cachedFile(for remote: URL) -> URL? {
        let key = Self.digest(of: remote)
        guard let file = currentFiles[key] else { return nil }
        if entries[file] != nil, FileManager.default.fileExists(atPath: file.path) { return file }
        removeEntry(file)
        return nil
    }

    private func download(_ remote: URL) async throws -> URL {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        let (data, response) = try await downloadData(request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw URLError(.cannotDecodeContentData) }
        let file = directory.appending(path: "\(Self.digest(of: remote))-\(UUID().uuidString).\(Self.fileExtension(of: data))")
        try data.write(to: file, options: .atomic)
        removeEntry(file)
        entries[file] = Entry(bytes: data.count, accessed: now())
        currentFiles[Self.digest(of: remote)] = file
        totalBytes += data.count
        touch(file)
        trim(protecting: [file])
        return file
    }

    /// 用地址算一个稳定的文件名。地址本身有斜杠和查询串，不能直接当文件名。
    private static func digest(of remote: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(remote.absoluteString.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// 按字节头认格式。认不出就当 JPEG——B 站的图绝大多数是 JPEG，
    /// 实际解码仍由 ImageIO 根据文件内容识别。
    private static func fileExtension(of data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        guard head.count >= 12 else { return "jpg" }

        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return "jpg" }
        if head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return "png" }
        if head[0] == 0x47, head[1] == 0x49, head[2] == 0x46 { return "gif" }
        // RIFF....WEBP
        if head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return "webp" }
        // ....ftyp（HEIC 及同族）
        if head[4] == 0x66, head[5] == 0x74, head[6] == 0x79, head[7] == 0x70 { return "heic" }
        return "jpg"
    }
}
