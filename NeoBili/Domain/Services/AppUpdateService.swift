import Foundation

public enum AppUpdateDownloadEvent: Equatable, Sendable {
    case progress(fraction: Double, completedBytes: Int64, totalBytes: Int64)
    case completed(URL)
}

public struct AppUpdateService: Sendable {
    public typealias FetchReleaseOperation = @Sendable () async throws -> AppUpdateRelease
    public typealias DownloadPackageOperation = @Sendable (URL, String) -> AsyncThrowingStream<AppUpdateDownloadEvent, Error>
    public typealias CleanupPackagesOperation = @Sendable () -> Void

    public var fetchLatestRelease: FetchReleaseOperation
    public var downloadPackage: DownloadPackageOperation
    public var cleanupPackages: CleanupPackagesOperation

    public init(
        fetchLatestRelease: @escaping FetchReleaseOperation = { throw ServiceError.unconfigured("appUpdate.fetchLatestRelease") },
        downloadPackage: @escaping DownloadPackageOperation = { _, _ in
            AsyncThrowingStream { $0.finish(throwing: ServiceError.unconfigured("appUpdate.downloadPackage")) }
        },
        cleanupPackages: @escaping CleanupPackagesOperation = {}
    ) {
        self.fetchLatestRelease = fetchLatestRelease
        self.downloadPackage = downloadPackage
        self.cleanupPackages = cleanupPackages
    }
}
