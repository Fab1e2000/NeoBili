#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import Observation
import UIKit

/// 管理应用更新检查、红点状态、SideStore/AltStore 唤起及 IPA 下载分享流程。
@MainActor
@Observable
final class AppUpdateStore {
    enum CheckState: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppUpdateRelease)
        case failed(String)
    }

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double, completedBytes: Int64, totalBytes: Int64)
        case readyToShare(URL)
        case failed(String)
    }

    enum ExternalInstaller: String, Equatable, CaseIterable {
        case sideStore
        case altStore

        var displayName: String {
            switch self {
            case .sideStore: "SideStore"
            case .altStore: "AltStore"
            }
        }

        var schemeURL: URL {
            switch self {
            case .sideStore: AppUpdateConstants.sideStoreAppURL
            case .altStore: AppUpdateConstants.altStoreAppURL
            }
        }

        func sourceURL(for feedURL: URL) -> URL {
            switch self {
            case .sideStore: AppUpdateConstants.sideStoreSourceURL(for: feedURL)
            case .altStore: AppUpdateConstants.altStoreSourceURL(for: feedURL)
            }
        }

        func installURL(for packageURL: URL) -> URL {
            switch self {
            case .sideStore: AppUpdateConstants.sideStoreInstallURL(for: packageURL)
            case .altStore: AppUpdateConstants.altStoreInstallURL(for: packageURL)
            }
        }
    }

    private let service: AppUpdateService
    private let defaults: UserDefaults
    private let currentVersionProvider: () -> String
    private let now: () -> Date
    private let canOpenURL: (URL) -> Bool
    private let openURL: (URL) async -> Bool

    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var didRunStartupCleanup = false

    private(set) var checkState: CheckState = .idle
    private(set) var downloadState: DownloadState = .idle
    private(set) var activeDownloadSource: AppUpdateDownloadSource = .github

    var autoCheckEnabled: Bool {
        didSet {
            defaults.set(autoCheckEnabled, forKey: AppUpdateConstants.autoCheckEnabledKey)
        }
    }

    private(set) var ignoredVersion: String? {
        didSet {
            if let ignoredVersion, !ignoredVersion.isEmpty {
                defaults.set(ignoredVersion, forKey: AppUpdateConstants.ignoredVersionKey)
            } else {
                defaults.removeObject(forKey: AppUpdateConstants.ignoredVersionKey)
            }
        }
    }

    private(set) var lastCheckDate: Date? {
        didSet {
            if let lastCheckDate {
                defaults.set(lastCheckDate.timeIntervalSince1970, forKey: AppUpdateConstants.lastCheckDateKey)
            } else {
                defaults.removeObject(forKey: AppUpdateConstants.lastCheckDateKey)
            }
        }
    }

    init(
        service: AppUpdateService,
        defaults: UserDefaults = .standard,
        currentVersionProvider: @escaping () -> String = AppUpdateStore.defaultCurrentVersion,
        now: @escaping () -> Date = Date.init,
        canOpenURL: @escaping (URL) -> Bool = { UIApplication.shared.canOpenURL($0) },
        openURL: @escaping (URL) async -> Bool = { await UIApplication.shared.open($0) }
    ) {
        self.service = service
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider
        self.now = now
        self.canOpenURL = canOpenURL
        self.openURL = openURL

        if defaults.object(forKey: AppUpdateConstants.autoCheckEnabledKey) != nil {
            self.autoCheckEnabled = defaults.bool(forKey: AppUpdateConstants.autoCheckEnabledKey)
        } else {
            self.autoCheckEnabled = true
        }
        self.ignoredVersion = defaults.string(forKey: AppUpdateConstants.ignoredVersionKey)
        if defaults.object(forKey: AppUpdateConstants.lastCheckDateKey) != nil {
            let timestamp = defaults.double(forKey: AppUpdateConstants.lastCheckDateKey)
            self.lastCheckDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        } else {
            self.lastCheckDate = nil
        }
    }

    var currentVersion: String {
        currentVersionProvider()
    }

    var availableRelease: AppUpdateRelease? {
        if case .available(let release) = checkState {
            return release
        }
        return nil
    }

    var isAvailableVersionIgnored: Bool {
        guard let release = availableRelease, let ignoredVersion else { return false }
        return release.version == ignoredVersion
    }

    /// 仅当发现新版本且未被用户忽略时显示入口红点。
    var showsUpdateBadge: Bool {
        availableRelease != nil && !isAvailableVersionIgnored
    }

    var installedInstaller: ExternalInstaller? {
        ExternalInstaller.allCases.first { canOpenURL($0.schemeURL) }
    }

    /// 启动时静默检查更新（受开关和 24 小时节流约束，失败不打扰用户）。
    func checkAutomaticallyIfNeeded() async {
        if !didRunStartupCleanup {
            didRunStartupCleanup = true
            service.cleanupPackages()
        }
        guard autoCheckEnabled else { return }
        if let lastCheckDate, now().timeIntervalSince(lastCheckDate) < AppUpdateConstants.autoCheckInterval {
            return
        }
        await performCheck(isManual: false)
    }

    /// 用户在「设置 → 关于」主动点击检查更新。
    func checkManually() async {
        await performCheck(isManual: true)
    }

    func ignoreAvailableVersion() {
        guard let release = availableRelease else { return }
        ignoredVersion = release.version
    }

    func clearIgnoredVersion() {
        ignoredVersion = nil
    }

    @discardableResult
    func openInInstaller(_ installer: ExternalInstaller, source: AppUpdateDownloadSource? = nil) async -> Bool {
        if let source, let release = availableRelease {
            return await openURL(installer.installURL(for: release.downloadURL(for: source)))
        }
        let feedURL = availableRelease?.sourceURL ?? AppUpdateConstants.sourceURL
        return await openURL(installer.sourceURL(for: feedURL))
    }

    @discardableResult
    func openGitHubReleases() async -> Bool {
        await openURL(AppUpdateConstants.githubReleasesURL)
    }

    func startDownload(source: AppUpdateDownloadSource = .github) {
        guard let release = availableRelease else { return }
        downloadTask?.cancel()
        activeDownloadSource = source
        downloadState = .downloading(progress: 0, completedBytes: 0, totalBytes: release.packageSize ?? 0)

        let downloadOperation = service.downloadPackage
        let targetURL = release.downloadURL(for: source)
        let fallbackTotal = release.packageSize ?? 0

        downloadTask = Task { [weak self] in
            do {
                let stream = downloadOperation(targetURL, release.version)
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self else { return }
                        switch event {
                        case .progress(let fraction, let completed, let total):
                            let resolvedTotal = total > 0 ? total : fallbackTotal
                            let resolvedFraction: Double
                            if total > 0 {
                                resolvedFraction = fraction
                            } else if resolvedTotal > 0 {
                                resolvedFraction = min(max(Double(completed) / Double(resolvedTotal), 0), 1)
                            } else {
                                resolvedFraction = 0
                            }
                            self.downloadState = .downloading(
                                progress: resolvedFraction,
                                completedBytes: completed,
                                totalBytes: resolvedTotal
                            )
                        case .completed(let fileURL):
                            self.downloadState = .readyToShare(fileURL)
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.downloadState = .idle
                }
            } catch let error as AppUpdateError where error == .cancelled {
                await MainActor.run {
                    self?.downloadState = .idle
                }
            } catch {
                await MainActor.run {
                    self?.downloadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        service.cleanupPackages()
        downloadState = .idle
    }

    func finishSharingPackage() {
        downloadTask?.cancel()
        downloadTask = nil
        service.cleanupPackages()
        downloadState = .idle
    }

    private func performCheck(isManual: Bool) async {
        checkTask?.cancel()
        if isManual {
            checkState = .checking
        }
        let fetch = service.fetchLatestRelease
        let task = Task { [weak self] in
            do {
                let release = try await fetch()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyCheckResult(release)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    if isManual {
                        self.checkState = .failed(error.localizedDescription)
                    }
                }
            }
        }
        checkTask = task
        await task.value
    }

    private func applyCheckResult(_ release: AppUpdateRelease) {
        lastCheckDate = now()
        if let localVersion = AppVersion(currentVersion), release.parsedVersion > localVersion {
            if let ignoredVersion,
               let ignoredParsed = AppVersion(ignoredVersion),
               release.parsedVersion > ignoredParsed {
                self.ignoredVersion = nil
            }
            checkState = .available(release)
        } else {
            if let ignoredVersion,
               let localVersion = AppVersion(currentVersion),
               let ignoredParsed = AppVersion(ignoredVersion),
               localVersion >= ignoredParsed {
                self.ignoredVersion = nil
            }
            checkState = .upToDate
        }
    }

    nonisolated static func defaultCurrentVersion() -> String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["NEOBILI_DEBUG_APP_VERSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
