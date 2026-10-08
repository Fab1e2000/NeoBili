import Foundation
import ImageIO
import CryptoKit

actor ImageFileCache {
    static let shared = ImageFileCache()

    private let directory: URL
    /// 同一张图并发请求时只下载一次。
    private var inFlight: [URL: Task<URL, Error>] = [:]

    /// QuickLook 靠扩展名认格式，所以按字节头判断真实格式，不信 URL 上的后缀
    /// ——B 站的图片地址常带 `@1e_1c.webp` 这类后缀，和实际内容未必一致。
    private static let knownExtensions = ["jpg", "png", "gif", "webp", "heic"]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "ImageViewer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func localFile(for remote: URL) async throws -> URL {
        if let cached = cachedFile(for: remote) { return cached }

        if let existing = inFlight[remote] { return try await existing.value }

        let task = Task<URL, Error> { try await download(remote) }
        inFlight[remote] = task
        defer { inFlight[remote] = nil }
        return try await task.value
    }

    private func cachedFile(for remote: URL) -> URL? {
        let name = Self.digest(of: remote)
        for ext in Self.knownExtensions {
            let candidate = directory.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func download(_ remote: URL) async throws -> URL {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")

        let (data, response) = try await AppNetwork.session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw URLError(.cannotDecodeContentData) }

        let file = directory.appending(path: "\(Self.digest(of: remote)).\(Self.fileExtension(of: data))")
        try data.write(to: file, options: .atomic)
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
    /// 而且 QuickLook 自己还会再嗅一次，扩展名只是给它的第一个提示。
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
