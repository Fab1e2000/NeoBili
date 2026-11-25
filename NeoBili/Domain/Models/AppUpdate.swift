import Foundation

/// 语义化版本值，按数字段比较（忽略前导 `v` 与尾部预发布后缀，尾部 0 视为相等）。
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public let components: [Int]

    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutPrefix = (trimmed.first == "v" || trimmed.first == "V")
            ? String(trimmed.dropFirst())
            : trimmed
        let core = withoutPrefix.split(maxSplits: 1, whereSeparator: { $0 == "-" || $0 == "+" }).first
            .map(String.init) ?? withoutPrefix
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        numbers.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty, let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        self.rawValue = withoutPrefix
        self.components = numbers
    }

    public var description: String { rawValue }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var normalized = components
        while normalized.count > 1, normalized.last == 0 {
            normalized.removeLast()
        }
        hasher.combine(normalized)
    }
}

public enum AppUpdateDownloadSource: String, CaseIterable, Identifiable, Sendable {
    case github
    case mirror

    public var id: String { rawValue }
}

public struct AppUpdateRelease: Equatable, Hashable, Sendable {
    public let version: String
    public let parsedVersion: AppVersion
    public let releaseDate: Date?
    public let releaseNotes: String
    public let downloadURL: URL
    public let packageSize: Int64?
    public let sourceURL: URL

    public init(
        version: String,
        parsedVersion: AppVersion,
        releaseDate: Date? = nil,
        releaseNotes: String = "",
        downloadURL: URL,
        packageSize: Int64? = nil,
        sourceURL: URL = AppUpdateConstants.sourceURL
    ) {
        self.version = version
        self.parsedVersion = parsedVersion
        self.releaseDate = releaseDate
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.packageSize = packageSize
        self.sourceURL = sourceURL
    }

    public func downloadURL(for source: AppUpdateDownloadSource) -> URL {
        switch source {
        case .github:
            return AppUpdateConstants.githubDownloadURL(forVersion: version) ?? downloadURL
        case .mirror:
            return downloadURL
        }
    }
}

public enum AppUpdateError: LocalizedError, Equatable, Sendable {
    case invalidFeed
    case appNotFound
    case invalidDownloadURL
    case downloadFailed(String)
    case cancelled
    case networkFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFeed:
            return String(localized: "更新源数据格式无效。")
        case .appNotFound:
            return String(localized: "更新源中未找到当前应用。")
        case .invalidDownloadURL:
            return String(localized: "安装包下载地址无效。")
        case .downloadFailed(let message):
            return message.isEmpty ? String(localized: "安装包下载失败，请稍后重试。") : message
        case .cancelled:
            return String(localized: "已取消下载。")
        case .networkFailed(let message):
            return message.isEmpty ? String(localized: "检查更新失败，请检查网络后重试。") : message
        }
    }
}

public enum AppUpdateConstants {
    public static let sourceURL = URL(string: "https://n015.top/neobili/apps.json")!
    public static let githubReleasesURL = URL(string: "https://github.com/Fab1e2000/NeoBili/releases/latest")!
    public static let bundleIdentifier = "com.elsterlee.NeoBili"

    public static let autoCheckEnabledKey = "neobili.appUpdate.autoCheckEnabled"
    public static let lastCheckDateKey = "neobili.appUpdate.lastCheckDate"
    public static let ignoredVersionKey = "neobili.appUpdate.ignoredVersion"
    public static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    public static let sideStoreAppURL = URL(string: "sidestore://")!
    public static let altStoreAppURL = URL(string: "altstore://")!

    public static func githubDownloadURL(forVersion version: String) -> URL? {
        let normalized = AppVersion(version)?.rawValue ?? version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return URL(string: "https://github.com/Fab1e2000/NeoBili/releases/download/v\(normalized)/NeoBili-v\(normalized)-unsigned.ipa")
    }

    public static func sideStoreSourceURL(for source: URL = sourceURL) -> URL {
        installerURL(scheme: "sidestore", host: "source", target: source)
    }

    public static func altStoreSourceURL(for source: URL = sourceURL) -> URL {
        installerURL(scheme: "altstore", host: "source", target: source)
    }

    public static func sideStoreInstallURL(for packageURL: URL) -> URL {
        installerURL(scheme: "sidestore", host: "install", target: packageURL)
    }

    public static func altStoreInstallURL(for packageURL: URL) -> URL {
        installerURL(scheme: "altstore", host: "install", target: packageURL)
    }

    private static func installerURL(scheme: String, host: String, target: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        return components.url ?? target
    }
}

/// 解析 SideStore / AltStore 软件源 JSON（`apps.json`）。
public enum AppUpdateSourceParser {
    private struct SourceDocument: Decodable {
        let sourceURL: String?
        let apps: [AppEntry]
    }

    private struct AppEntry: Decodable {
        let bundleIdentifier: String?
        let version: String?
        let versionDate: String?
        let versionDescription: String?
        let downloadURL: String?
        let size: Int64?
        let versions: [VersionEntry]?
    }

    private struct VersionEntry: Decodable {
        let version: String?
        let date: String?
        let localizedDescription: String?
        let downloadURL: String?
        let size: Int64?
    }

    public static func parse(
        data: Data,
        bundleIdentifier: String = AppUpdateConstants.bundleIdentifier,
        fallbackSourceURL: URL = AppUpdateConstants.sourceURL
    ) throws -> AppUpdateRelease {
        let document: SourceDocument
        do {
            document = try JSONDecoder().decode(SourceDocument.self, from: data)
        } catch {
            throw AppUpdateError.invalidFeed
        }

        let targetID = normalizedBundleIdentifier(bundleIdentifier)
        guard let app = document.apps.first(where: {
            guard let id = $0.bundleIdentifier else { return false }
            return normalizedBundleIdentifier(id) == targetID
        }) else {
            throw AppUpdateError.appNotFound
        }

        let sourceURL = document.sourceURL.flatMap(URL.init(string:)) ?? fallbackSourceURL
        let latestEntry = app.versions?.first

        let rawVersion = (app.version?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? latestEntry?.version?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let versionString = rawVersion, let parsedVersion = AppVersion(versionString) else {
            throw AppUpdateError.invalidFeed
        }

        let rawDownload = (app.downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? latestEntry?.downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let downloadString = rawDownload,
              let downloadURL = URL(string: downloadString),
              let scheme = downloadURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw AppUpdateError.invalidDownloadURL
        }

        let notes = app.versionDescription ?? latestEntry?.localizedDescription ?? ""
        let dateString = app.versionDate ?? latestEntry?.date
        let releaseDate = dateString.flatMap(parseISO8601Date)
        let size = app.size ?? latestEntry?.size

        return AppUpdateRelease(
            version: parsedVersion.rawValue,
            parsedVersion: parsedVersion,
            releaseDate: releaseDate,
            releaseNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            downloadURL: downloadURL,
            packageSize: size,
            sourceURL: sourceURL
        )
    }

    private static func normalizedBundleIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".regression") {
            return String(trimmed.dropLast(".regression".count))
        }
        return trimmed
    }

    private static func parseISO8601Date(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: string) { return date }

        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: string)
    }
}
